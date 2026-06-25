package com.namecallfilter.glacier.cast

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.mediarouter.media.MediaRouteSelector
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.namecallfilter.glacier.streamproxy.CastRelayServer
import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import com.namecallfilter.glacier.streamproxy.StreamProxySessionRegistry
import java.util.Locale

internal const val PENDING_LOAD_RETRY_DELAY_MS = 500L
internal const val MAX_PENDING_LOAD_RETRY_WINDOW_MS = 30_000L
internal const val STARTUP_LOAD_DEBOUNCE_MS = 500L
internal const val EXPECTED_CAST_RECEIVER_VERSION = "2026-06-24-1"

class GlacierCastController(
    context: Context,
    private val onStateChanged: (Map<String, Any?>) -> Unit = {},
    private val onRoutesChanged: (Map<String, Any?>) -> Unit = {},
) {
    private val applicationContext = context.applicationContext
    private val receiverApplicationId =
        GlacierCastReceiverConfig.receiverApplicationId(applicationContext)
    private val receiverApplicationIdDescription =
        GlacierCastReceiverConfig.maskedReceiverApplicationId(applicationContext)
    private val relayServer = CastRelayServer(::log)
    private val sessionListener = CastSessionListener()
    private val mediaRouter: MediaRouter by lazy {
        MediaRouter.getInstance(applicationContext)
    }
    private val routeSelector = MediaRouteSelector.Builder()
        .addControlCategory(CastMediaControlIntent.categoryForCast(receiverApplicationId))
        .build()
    private val routeCallback = CastRouteCallback()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingLoadRetryRunnable = Runnable {
        loadRetryScheduled = false
        if (pendingLoad && currentSession()?.isConnected == true) {
            loadCurrent()
        }
    }
    private val startupLoadDebounceRunnable = Runnable {
        startupLoadDebounceScheduled = false
        if (pendingLoad && currentSession()?.isConnected == true) {
            loadCurrent()
        }
    }

    @Volatile
    private var castContext: CastContext? = null

    @Volatile
    private var streamContext: CastStreamContext? = null

    @Volatile
    private var pendingLoad = false

    @Volatile
    private var pendingLoadStartedAtMs: Long? = null

    @Volatile
    private var loadRetryScheduled = false

    @Volatile
    private var startupLoadDebounceScheduled = false

    @Volatile
    private var awaitingReceiverMedia = false

    @Volatile
    private var receiverLatencyMs: Long? = null

    @Volatile
    private var receiverRuntimeMismatchLogged = false

    @Volatile
    private var suspendedLocalWebViewIdentifier: Long? = null

    @Volatile
    private var routeDiscoveryActive = false

    @Volatile
    private var connectingRouteId: String? = null

    @Volatile
    private var connectingRouteName: String? = null

    @Volatile
    private var keepAliveActive = false

    init {
        runCatching {
            CastContext.getSharedInstance(applicationContext)
        }.onSuccess { context ->
            castContext = context
            context.sessionManager.addSessionManagerListener(
                sessionListener,
                CastSession::class.java,
            )
            initializeExistingSession(context.sessionManager.currentCastSession)
        }.onFailure { error ->
            Log.d(LOG_TAG, "cast action=init_failed reason=${error.javaClass.simpleName}")
        }
    }

    fun updateContext(context: CastStreamContext) {
        val previousContext = streamContext
        streamContext = context
        updateRelay(context)

        when (
            contextUpdateLoadAction(
                sessionConnected = currentSession()?.isConnected == true,
                pendingLoad = pendingLoad,
                previous = previousContext,
                next = context,
            )
        ) {
            CastContextUpdateLoadAction.LOAD_NOW -> loadCurrent()
            CastContextUpdateLoadAction.DEBOUNCE_STARTUP -> scheduleStartupLoadDebounce()
            CastContextUpdateLoadAction.NONE -> Unit
        }
    }

    fun prepareLoad() {
        pendingLoad = true
        pendingLoadStartedAtMs = SystemClock.elapsedRealtime()
        awaitingReceiverMedia = false
        cancelLoadTimers()
        if (currentSession()?.isConnected == true) {
            scheduleStartupLoadDebounce()
        }
    }

    fun startRouteDiscovery() {
        routeDiscoveryActive = true
        runCatching {
            mediaRouter.addCallback(
                routeSelector,
                routeCallback,
                MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY or
                    MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN,
            )
            emitRoutes()
        }.onFailure { error ->
            emitRoutes(error = "Unable to search for Cast devices.")
            Log.d(
                LOG_TAG,
                "cast_routes action=start_failed reason=${error.javaClass.simpleName} " +
                    "message=${error.message}",
                error,
            )
        }
    }

    fun stopRouteDiscovery() {
        if (!routeDiscoveryActive) return

        routeDiscoveryActive = false
        runCatching {
            mediaRouter.removeCallback(routeCallback)
            emitRoutes()
        }.onFailure { error ->
            Log.d(
                LOG_TAG,
                "cast_routes action=stop_failed reason=${error.javaClass.simpleName} " +
                    "message=${error.message}",
                error,
            )
        }
    }

    fun selectRoute(routeId: String) {
        val session = currentSession()
        if (session?.isConnected == true) {
            emitState(session)
            emitRoutes()
            return
        }

        val route = castRoutes().firstOrNull { route -> route.id == routeId }
        if (route == null) {
            connectingRouteId = null
            connectingRouteName = null
            emitRoutes(error = "Cast device is no longer available.")
            return
        }

        prepareLoad()
        connectingRouteId = route.id
        connectingRouteName = route.name.toString()
        emitRoutes()

        runCatching {
            route.select()
        }.onFailure { error ->
            pendingLoad = false
            resetLoadAttemptState()
            connectingRouteId = null
            connectingRouteName = null
            emitRoutes(error = "Unable to connect to Cast device.")
            Log.d(
                LOG_TAG,
                "cast_routes action=select_failed reason=${error.javaClass.simpleName} " +
                    "message=${error.message}",
                error,
            )
        }
    }

    fun stopCasting() {
        pendingLoad = false
        resetLoadAttemptState()
        restoreLocalWebViewAfterCast()
        receiverLatencyMs = null
        connectingRouteId = null
        connectingRouteName = null
        castContext?.sessionManager?.endCurrentSession(true)
        relayServer.close()
        stopKeepAlive()
        emitDisconnected()
        emitRoutes()
    }

    private fun loadCurrent() {
        cancelStartupLoadDebounce()
        if (pendingLoadStartedAtMs == null) {
            pendingLoadStartedAtMs = SystemClock.elapsedRealtime()
        }

        val context = streamContext
        if (context == null) {
            pendingLoad = true
            logLoadFailure(CastLoadAttemptResult.MISSING_CONTEXT)
            schedulePendingLoadRetry(CastLoadAttemptResult.MISSING_CONTEXT)
            return
        }

        val router = StreamProxySessionRegistry.routerFor(context.webViewIdentifier)
        if (router == null) {
            pendingLoad = true
            logLoadFailure(CastLoadAttemptResult.MISSING_ROUTER)
            schedulePendingLoadRetry(CastLoadAttemptResult.MISSING_ROUTER)
            return
        }

        updateRelay(context)

        val manifestUrl = router.latestUsherManifestUrl(context.channelLogin)
        if (manifestUrl == null) {
            pendingLoad = true
            logLoadFailure(
                result = CastLoadAttemptResult.MISSING_MANIFEST,
                detail = "channel=${context.channelLogin}",
            )
            schedulePendingLoadRetry(CastLoadAttemptResult.MISSING_MANIFEST)
            return
        }

        val relayUrl = relayServer.relayUrlFor(
            sourceUrl = manifestUrl,
            selectedQuality = context.quality,
        )
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_GENERIC).apply {
            putString(MediaMetadata.KEY_TITLE, context.title)
            context.subtitle
                ?.takeIf(String::isNotBlank)
                ?.let { subtitle ->
                    putString(MediaMetadata.KEY_SUBTITLE, subtitle)
                }
        }
        val mediaInfo = MediaInfo.Builder(relayUrl, relayUrl)
            .setStreamType(MediaInfo.STREAM_TYPE_LIVE)
            .setContentType(HLS_CONTENT_TYPE)
            .setContentUrl(relayUrl)
            .setEntity(relayUrl)
            .setMetadata(metadata)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setMediaInfo(mediaInfo)
            .setAutoplay(true)
            .build()

        val remoteMediaClient = currentSession()?.remoteMediaClient
        if (remoteMediaClient == null) {
            pendingLoad = true
            logLoadFailure(CastLoadAttemptResult.MISSING_REMOTE_MEDIA_CLIENT)
            schedulePendingLoadRetry(CastLoadAttemptResult.MISSING_REMOTE_MEDIA_CLIENT)
            return
        }

        setLocalWebViewCastSuspensionTarget(context.webViewIdentifier)
        pendingLoad = false
        awaitingReceiverMedia = true
        remoteMediaClient.load(request).setResultCallback { result ->
            val status = result.status
            if (status.isSuccess) {
                confirmReceiverMediaLoaded()
            } else {
                awaitingReceiverMedia = false
                pendingLoad = true
                Log.d(
                    LOG_TAG,
                    "cast action=load_result success=false " +
                        "status=${status.statusCode} " +
                        "message=${status.statusMessage ?: ""} " +
                        "relay=$relayUrl",
                )
                schedulePendingLoadRetry(CastLoadAttemptResult.LOAD_RESULT_FAILED)
            }
        }
        emitState(currentSession())
        log("cast action=load relay=$relayUrl quality=${context.quality}")
    }

    private fun logLoadFailure(result: CastLoadAttemptResult, detail: String? = null) {
        val detailText = detail?.let { value -> " $value" } ?: ""
        Log.d(
            LOG_TAG,
            "cast action=load_failed reason=${result.logReason()}$detailText " +
                "age_ms=${pendingLoadAgeMs()}",
        )
    }

    private fun schedulePendingLoadRetry(result: CastLoadAttemptResult) {
        val decision = pendingLoadRetryDecision(
            result = result,
            pendingLoad = pendingLoad,
            sessionConnected = currentSession()?.isConnected == true,
            pendingLoadAgeMs = pendingLoadAgeMs(),
        )
        if (!decision.shouldRetry) {
            if (
                pendingLoad &&
                currentSession()?.isConnected == true &&
                pendingLoadAgeMs() > MAX_PENDING_LOAD_RETRY_WINDOW_MS
            ) {
                Log.d(
                    LOG_TAG,
                    "cast action=load_retry_expired " +
                        "last_reason=${result.logReason()} " +
                        "age_ms=${pendingLoadAgeMs()}",
                )
            }
            return
        }
        if (loadRetryScheduled) return

        loadRetryScheduled = true
        mainHandler.postDelayed(pendingLoadRetryRunnable, decision.delayMs)
    }

    private fun scheduleStartupLoadDebounce() {
        if (!pendingLoad || currentSession()?.isConnected != true) return

        if (startupLoadDebounceScheduled) {
            mainHandler.removeCallbacks(startupLoadDebounceRunnable)
        }
        startupLoadDebounceScheduled = true
        mainHandler.postDelayed(startupLoadDebounceRunnable, STARTUP_LOAD_DEBOUNCE_MS)
        log("cast action=startup_load_debounce delay_ms=$STARTUP_LOAD_DEBOUNCE_MS")
    }

    private fun cancelLoadTimers() {
        mainHandler.removeCallbacks(pendingLoadRetryRunnable)
        mainHandler.removeCallbacks(startupLoadDebounceRunnable)
        loadRetryScheduled = false
        startupLoadDebounceScheduled = false
    }

    private fun cancelStartupLoadDebounce() {
        if (!startupLoadDebounceScheduled) return

        mainHandler.removeCallbacks(startupLoadDebounceRunnable)
        startupLoadDebounceScheduled = false
    }

    private fun resetLoadAttemptState() {
        cancelLoadTimers()
        pendingLoadStartedAtMs = null
        awaitingReceiverMedia = false
    }

    private fun pendingLoadAgeMs(): Long {
        val startedAtMs = pendingLoadStartedAtMs ?: return 0L
        return (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(0L)
    }

    private fun confirmReceiverMediaLoaded() {
        pendingLoad = false
        resetLoadAttemptState()
    }

    private fun updateRelay(context: CastStreamContext) {
        val router = StreamProxySessionRegistry.getOrCreateRouter(context.webViewIdentifier)
        relayServer.update(
            router = router,
            config = context.config,
        )
    }

    private fun setLocalWebViewCastSuspensionTarget(targetWebViewIdentifier: Long?) {
        val change = localWebViewCastSuspensionChange(
            currentSuspendedWebViewIdentifier = suspendedLocalWebViewIdentifier,
            targetWebViewIdentifier = targetWebViewIdentifier,
        )

        change.resumeWebViewIdentifier?.let { webViewIdentifier ->
            StreamProxySessionRegistry.setLocalPlaybackSuspendedForCast(
                webViewIdentifier = webViewIdentifier,
                suspended = false,
            )
            log("cast action=local_webview_resume web_view=$webViewIdentifier")
        }
        change.suspendWebViewIdentifier?.let { webViewIdentifier ->
            StreamProxySessionRegistry.setLocalPlaybackSuspendedForCast(
                webViewIdentifier = webViewIdentifier,
                suspended = true,
            )
            log("cast action=local_webview_suspend web_view=$webViewIdentifier")
        }

        suspendedLocalWebViewIdentifier = targetWebViewIdentifier
    }

    private fun restoreLocalWebViewAfterCast() {
        setLocalWebViewCastSuspensionTarget(null)
    }

    private fun startKeepAlive() {
        if (keepAliveActive) return

        keepAliveActive = true
        runCatching {
            CastRelayKeepAliveService.start(applicationContext)
        }.onFailure { error ->
            keepAliveActive = false
            log("cast_keep_alive action=start_failed reason=${error.javaClass.simpleName}")
        }
    }

    private fun stopKeepAlive() {
        if (!keepAliveActive) return

        keepAliveActive = false
        runCatching {
            CastRelayKeepAliveService.stop(applicationContext)
        }.onFailure { error ->
            log("cast_keep_alive action=stop_failed reason=${error.javaClass.simpleName}")
        }
    }

    private fun currentSession(): CastSession? {
        return castContext?.sessionManager?.currentCastSession
    }

    private fun initializeExistingSession(session: CastSession?) {
        val actions = existingCastSessionStartupActions(
            sessionConnected = session?.isConnected == true,
            pendingLoad = pendingLoad,
        )

        if (actions.startKeepAlive) {
            startKeepAlive()
        }
        if (actions.attachReceiverChannel && session != null) {
            attachReceiverChannel(session)
        }
        emitState(session)
        if (actions.emitRoutes) {
            emitRoutes()
        }
        if (actions.loadCurrent) {
            scheduleStartupLoadDebounce()
        }
    }

    private fun attachReceiverChannel(session: CastSession) {
        runCatching {
            session.setMessageReceivedCallbacks(CAST_NAMESPACE) { _, _, message ->
                val status = CastReceiverMessageParser.parse(message)
                if (status != null) {
                    receiverLatencyMs = status.latencyMs ?: receiverLatencyMs
                    if (awaitingReceiverMedia && receiverStatusConfirmsLoad(status)) {
                        confirmReceiverMediaLoaded()
                    }
                    logReceiverStatus(status)
                    emitState(session)
                    return@setMessageReceivedCallbacks
                }

                val diagnostic = CastReceiverMessageParser.parseDiagnostic(message)
                    ?: return@setMessageReceivedCallbacks
                if (awaitingReceiverMedia && receiverDiagnosticConfirmsLoad(diagnostic)) {
                    confirmReceiverMediaLoaded()
                }
                logReceiverDiagnostic(diagnostic)
            }
        }.onFailure { error ->
            log("cast action=receiver_channel_failed reason=${error.javaClass.simpleName}")
        }
    }

    private fun logReceiverStatus(status: CastReceiverStatus) {
        if (shouldLogReceiverStatus()) {
            Log.d(LOG_TAG, receiverStatusLogLine(status))
        }
        if (!receiverRuntimeMismatchLogged && shouldLogDiagnostics()) {
            val mismatch = receiverRuntimeMismatchLogLine(status)
            if (mismatch != null) {
                receiverRuntimeMismatchLogged = true
                Log.d(LOG_TAG, mismatch)
            }
        }
    }

    private fun logReceiverDiagnostic(diagnostic: CastReceiverDiagnostic) {
        if (shouldLogDiagnostics()) {
            Log.d(LOG_TAG, receiverDiagnosticLogLine(diagnostic))
        }
    }

    private fun shouldLogReceiverStatus(): Boolean {
        return shouldLogDiagnostics()
    }

    private fun shouldLogDiagnostics(): Boolean {
        return streamContext?.config?.debugLogging == true ||
            (applicationContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun detachReceiverChannel(session: CastSession) {
        runCatching {
            session.removeMessageReceivedCallbacks(CAST_NAMESPACE)
        }
    }

    private fun emitState(session: CastSession? = currentSession()) {
        val isCasting = session?.isConnected == true
        onStateChanged(
            mapOf(
                "isCasting" to isCasting,
                "receiverName" to session
                    ?.takeIf { isCasting }
                    ?.castDevice
                    ?.friendlyName,
                "latencyMs" to receiverLatencyMs.takeIf { isCasting },
            ),
        )
    }

    private fun emitRoutes(error: String? = null) {
        val isCasting = currentSession()?.isConnected == true
        onRoutesChanged(
            mapOf(
                "isSearching" to routeDiscoveryActive,
                "isConnecting" to (!isCasting && connectingRouteId != null),
                "connectingRouteName" to connectingRouteName,
                "routes" to castRoutes().map { route ->
                    mapOf(
                        "id" to route.id,
                        "name" to route.name.toString(),
                        "description" to route.description?.toString(),
                    )
                },
                "error" to error,
            ),
        )
    }

    private fun castRoutes(): List<MediaRouter.RouteInfo> {
        return mediaRouter.routes.filter { route ->
            route.isEnabled &&
                !route.isDefault &&
                route.matchesSelector(routeSelector)
        }
    }

    private fun emitDisconnected() {
        onStateChanged(
            mapOf(
                "isCasting" to false,
                "receiverName" to null,
                "latencyMs" to null,
            ),
        )
    }

    private fun log(message: String) {
        if (shouldLogDiagnostics()) {
            Log.d(LOG_TAG, message)
        }
    }

    private inner class CastSessionListener : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            emitRoutes()
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            receiverLatencyMs = null
            receiverRuntimeMismatchLogged = false
            connectingRouteId = null
            connectingRouteName = null
            startKeepAlive()
            attachReceiverChannel(session)
            emitState(session)
            emitRoutes()
            if (pendingLoad) {
                scheduleStartupLoadDebounce()
            }
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            pendingLoad = false
            resetLoadAttemptState()
            restoreLocalWebViewAfterCast()
            receiverLatencyMs = null
            receiverRuntimeMismatchLogged = false
            connectingRouteId = null
            connectingRouteName = null
            stopKeepAlive()
            emitDisconnected()
            emitRoutes(error = "Unable to connect to Cast device.")
            Log.d(
                LOG_TAG,
                "cast action=session_start_failed error=$error " +
                    "status=${castStatusName(error)} " +
                    "receiver=$receiverApplicationIdDescription",
            )
        }

        override fun onSessionEnding(session: CastSession) {
            detachReceiverChannel(session)
        }

        override fun onSessionEnded(session: CastSession, error: Int) {
            pendingLoad = false
            resetLoadAttemptState()
            restoreLocalWebViewAfterCast()
            receiverLatencyMs = null
            receiverRuntimeMismatchLogged = false
            connectingRouteId = null
            connectingRouteName = null
            relayServer.close()
            stopKeepAlive()
            emitDisconnected()
            emitRoutes()
            if (error != 0) {
                Log.d(
                    LOG_TAG,
                    "cast action=session_ended error=$error " +
                        "status=${castStatusName(error)} " +
                        "receiver=$receiverApplicationIdDescription",
                )
            }
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) = Unit

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            receiverRuntimeMismatchLogged = false
            connectingRouteId = null
            connectingRouteName = null
            startKeepAlive()
            attachReceiverChannel(session)
            emitState(session)
            emitRoutes()
            if (pendingLoad) {
                scheduleStartupLoadDebounce()
            }
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            pendingLoad = false
            resetLoadAttemptState()
            restoreLocalWebViewAfterCast()
            receiverLatencyMs = null
            receiverRuntimeMismatchLogged = false
            connectingRouteId = null
            connectingRouteName = null
            stopKeepAlive()
            emitDisconnected()
            emitRoutes(error = "Unable to reconnect to Cast device.")
            Log.d(
                LOG_TAG,
                "cast action=session_resume_failed error=$error " +
                    "status=${castStatusName(error)} " +
                    "receiver=$receiverApplicationIdDescription",
            )
        }

        override fun onSessionSuspended(session: CastSession, reason: Int) {
            emitState(session)
            log("cast action=session_suspended reason=$reason")
        }
    }

    private inner class CastRouteCallback : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) {
            emitRoutes()
        }

        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) {
            emitRoutes()
        }

        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) {
            if (route.id == connectingRouteId) {
                connectingRouteId = null
                connectingRouteName = null
            }
            emitRoutes()
        }

        override fun onRouteSelected(
            router: MediaRouter,
            route: MediaRouter.RouteInfo,
            reason: Int,
        ) {
            connectingRouteId = route.id
            connectingRouteName = route.name.toString()
            emitRoutes()
        }

        override fun onRouteUnselected(
            router: MediaRouter,
            route: MediaRouter.RouteInfo,
            reason: Int,
        ) {
            if (route.id == connectingRouteId) {
                connectingRouteId = null
                connectingRouteName = null
            }
            emitRoutes()
        }
    }

    private companion object {
        private const val LOG_TAG = "GlacierCast"
        private const val CAST_NAMESPACE = "urn:x-cast:com.namecallfilter.glacier.cast"
        private const val HLS_CONTENT_TYPE = "application/x-mpegURL"

        private fun castStatusName(error: Int): String {
            return when (error) {
                0 -> "SUCCESS"
                2001 -> "TIMEOUT"
                2002 -> "CANCELED"
                2003 -> "INTERRUPTED"
                2004 -> "APPLICATION_NOT_FOUND"
                2005 -> "APPLICATION_NOT_RUNNING"
                2100 -> "AUTHENTICATION_FAILED"
                else -> "UNKNOWN"
            }
        }
    }
}

data class CastStreamContext(
    val webViewIdentifier: Long,
    val channelLogin: String,
    val title: String,
    val subtitle: String?,
    val quality: String?,
    val config: StreamProxyConfig,
) {
    fun requiresReceiverReloadFrom(previous: CastStreamContext?): Boolean {
        if (previous == null) return false

        return webViewIdentifier != previous.webViewIdentifier ||
            channelLogin != previous.channelLogin ||
            quality != previous.quality
    }
}

internal enum class CastContextUpdateLoadAction {
    NONE,
    LOAD_NOW,
    DEBOUNCE_STARTUP,
}

internal fun contextUpdateLoadAction(
    sessionConnected: Boolean,
    pendingLoad: Boolean,
    previous: CastStreamContext?,
    next: CastStreamContext,
): CastContextUpdateLoadAction {
    if (!sessionConnected) return CastContextUpdateLoadAction.NONE
    if (pendingLoad) return CastContextUpdateLoadAction.DEBOUNCE_STARTUP
    if (next.requiresReceiverReloadFrom(previous)) return CastContextUpdateLoadAction.LOAD_NOW

    return CastContextUpdateLoadAction.NONE
}

internal fun shouldLoadCurrentForContextUpdate(
    sessionConnected: Boolean,
    pendingLoad: Boolean,
    previous: CastStreamContext?,
    next: CastStreamContext,
): Boolean {
    return contextUpdateLoadAction(
        sessionConnected = sessionConnected,
        pendingLoad = pendingLoad,
        previous = previous,
        next = next,
    ) != CastContextUpdateLoadAction.NONE
}

internal enum class CastLoadAttemptResult {
    STARTED,
    MISSING_CONTEXT,
    MISSING_ROUTER,
    MISSING_MANIFEST,
    MISSING_REMOTE_MEDIA_CLIENT,
    LOAD_RESULT_FAILED,
}

internal data class PendingLoadRetryDecision(
    val shouldRetry: Boolean,
    val delayMs: Long,
)

internal fun pendingLoadRetryDecision(
    result: CastLoadAttemptResult,
    pendingLoad: Boolean,
    sessionConnected: Boolean,
    pendingLoadAgeMs: Long,
): PendingLoadRetryDecision {
    if (
        result == CastLoadAttemptResult.STARTED ||
        !pendingLoad ||
        !sessionConnected ||
        pendingLoadAgeMs > MAX_PENDING_LOAD_RETRY_WINDOW_MS
    ) {
        return PendingLoadRetryDecision(
            shouldRetry = false,
            delayMs = 0L,
        )
    }

    return PendingLoadRetryDecision(
        shouldRetry = true,
        delayMs = PENDING_LOAD_RETRY_DELAY_MS,
    )
}

internal fun receiverStatusConfirmsLoad(status: CastReceiverStatus): Boolean {
    val playerState = status.playerState
        ?.trim()
        ?.uppercase(Locale.US)

    return playerState == "BUFFERING" ||
        playerState == "PLAYING" ||
        receiverHasMediaTimeline(status)
}

internal fun receiverDiagnosticConfirmsLoad(diagnostic: CastReceiverDiagnostic): Boolean {
    return diagnostic.action.equals("load", ignoreCase = true)
}

internal fun receiverHasMediaTimeline(status: CastReceiverStatus): Boolean {
    return status.currentTimeSec != null &&
        status.rangeEndSec != null
}

internal data class LocalWebViewCastSuspensionChange(
    val suspendWebViewIdentifier: Long?,
    val resumeWebViewIdentifier: Long?,
)

internal fun localWebViewCastSuspensionChange(
    currentSuspendedWebViewIdentifier: Long?,
    targetWebViewIdentifier: Long?,
): LocalWebViewCastSuspensionChange {
    if (currentSuspendedWebViewIdentifier == targetWebViewIdentifier) {
        return LocalWebViewCastSuspensionChange(
            suspendWebViewIdentifier = null,
            resumeWebViewIdentifier = null,
        )
    }

    return LocalWebViewCastSuspensionChange(
        suspendWebViewIdentifier = targetWebViewIdentifier,
        resumeWebViewIdentifier = currentSuspendedWebViewIdentifier,
    )
}

private fun CastLoadAttemptResult.logReason(): String {
    return when (this) {
        CastLoadAttemptResult.STARTED -> "started"
        CastLoadAttemptResult.MISSING_CONTEXT -> "missing_context"
        CastLoadAttemptResult.MISSING_ROUTER -> "missing_router"
        CastLoadAttemptResult.MISSING_MANIFEST -> "missing_manifest"
        CastLoadAttemptResult.MISSING_REMOTE_MEDIA_CLIENT -> "missing_remote_media_client"
        CastLoadAttemptResult.LOAD_RESULT_FAILED -> "load_result_failed"
    }
}

internal fun receiverStatusLogLine(status: CastReceiverStatus): String {
    return "cast action=receiver_status " +
        "latency_ms=${status.latencyMs ?: -1} " +
        "seekable_latency_ms=${status.seekableLatencyMs ?: -1} " +
        "current_sec=${status.currentTimeSec ?: -1.0} " +
        "range_start_sec=${status.rangeStartSec ?: -1.0} " +
        "range_end_sec=${status.rangeEndSec ?: -1.0} " +
        "live_edge_sec=${status.liveEdgeTimeSec ?: -1.0} " +
        "target_sec=${status.targetLatencySec ?: -1.0} " +
        "max_sec=${status.maxLatencySec ?: -1.0} " +
        "latency_reference=${status.latencyReference ?: ""} " +
        "buffering=${status.buffering ?: ""} " +
        "buffering_age_ms=${status.bufferingAgeMs ?: -1} " +
        "player_state=${sanitizeReceiverLogValue(status.playerState)} " +
        "playback_rate=${status.playbackRate ?: -1.0} " +
        "receiver_version=${sanitizeReceiverLogValue(status.receiverVersion)}"
}

internal fun receiverRuntimeMismatchLogLine(status: CastReceiverStatus): String? {
    if (status.receiverVersion == EXPECTED_CAST_RECEIVER_VERSION) return null

    val missingFields = receiverRuntimeMissingFields(status)
    val actualVersion = status.receiverVersion ?: "missing"
    return "cast action=receiver_runtime_mismatch " +
        "expected_version=$EXPECTED_CAST_RECEIVER_VERSION " +
        "actual_version=${sanitizeReceiverLogValue(actualVersion)} " +
        "missing_fields=${missingFields.joinToString(",")}"
}

private fun receiverRuntimeMissingFields(status: CastReceiverStatus): List<String> {
    return buildList {
        if (status.receiverVersion == null) add("receiverVersion")
        if (status.buffering == null) add("buffering")
        if (status.playerState == null) add("playerState")
        if (status.playbackRate == null) add("playbackRate")
    }
}

internal fun receiverDiagnosticLogLine(diagnostic: CastReceiverDiagnostic): String {
    val fields = diagnostic.fields.entries.joinToString(" ") { (key, value) ->
        "$key=${sanitizeReceiverLogValue(value)}"
    }
    return "cast action=receiver_diagnostic " +
        "receiver_action=${sanitizeReceiverLogValue(diagnostic.action)}" +
        if (fields.isBlank()) "" else " $fields"
}

private fun sanitizeReceiverLogValue(value: Any?): String {
    return value
        ?.toString()
        ?.replace(Regex("\\s+"), "_")
        ?.take(160)
        .orEmpty()
}

internal data class ExistingCastSessionStartupActions(
    val attachReceiverChannel: Boolean,
    val startKeepAlive: Boolean,
    val emitRoutes: Boolean,
    val loadCurrent: Boolean,
)

internal fun existingCastSessionStartupActions(
    sessionConnected: Boolean,
    pendingLoad: Boolean,
): ExistingCastSessionStartupActions {
    return ExistingCastSessionStartupActions(
        attachReceiverChannel = sessionConnected,
        startKeepAlive = sessionConnected,
        emitRoutes = sessionConnected,
        loadCurrent = sessionConnected && pendingLoad,
    )
}
