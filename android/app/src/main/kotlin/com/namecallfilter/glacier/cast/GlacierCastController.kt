package com.namecallfilter.glacier.cast

import android.content.Context
import android.os.Handler
import android.os.Looper
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
import com.namecallfilter.glacier.streamproxy.CastMode
import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import com.namecallfilter.glacier.streamproxy.StreamProxySessionRegistry
import org.json.JSONObject

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

    @Volatile
    private var castContext: CastContext? = null

    @Volatile
    private var streamContext: CastStreamContext? = null

    @Volatile
    private var pendingLoad = false

    @Volatile
    private var receiverLatencyMs: Long? = null

    @Volatile
    private var receiverStatusMessage: String? = null

    @Volatile
    private var activeCastMode: CastMode = CastMode.STABLE_HLS

    @Volatile
    private var phoneWebRtcGatewayActive = false

    @Volatile
    private var phoneWebRtcGatewayRequestPath: String? = null

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
            emitState(context.sessionManager.currentCastSession)
        }.onFailure { error ->
            Log.d(LOG_TAG, "cast action=init_failed reason=${error.javaClass.simpleName}")
        }
    }

    fun updateContext(context: CastStreamContext) {
        streamContext = context
        updateRelay(context)

        if (pendingLoad && currentSession()?.isConnected == true) {
            loadCurrent()
        }
    }

    fun prepareLoad() {
        pendingLoad = true
        if (currentSession()?.isConnected == true) {
            loadCurrent()
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

    fun stopCasting(reason: String = "unknown") {
        log("cast action=stop_requested reason=$reason mode=${castModeLogName(activeCastMode)}")
        pendingLoad = false
        receiverLatencyMs = null
        receiverStatusMessage = null
        activeCastMode = CastMode.STABLE_HLS
        connectingRouteId = null
        connectingRouteName = null
        castContext?.sessionManager?.endCurrentSession(true)
        stopPhoneWebRtcGateway()
        relayServer.close()
        stopKeepAlive()
        emitDisconnected()
        emitRoutes()
    }

    private fun loadCurrent() {
        val context = streamContext ?: return
        updateRelay(context)

        when (context.config.castMode) {
            CastMode.STABLE_HLS -> loadStableHls(context)
            CastMode.LOW_LATENCY -> startWebRtc(context)
        }
    }

    private fun loadStableHls(context: CastStreamContext) {
        activeCastMode = CastMode.STABLE_HLS
        receiverStatusMessage = null
        stopPhoneWebRtcGateway()

        val router = StreamProxySessionRegistry.routerFor(context.webViewIdentifier)
        if (router == null) {
            log("cast action=load_failed reason=missing_router")
            return
        }

        val manifestUrl = router.latestUsherManifestUrl(context.channelLogin)
        if (manifestUrl == null) {
            log("cast action=load_failed reason=missing_manifest channel=${context.channelLogin}")
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
            log("cast action=load_failed reason=missing_remote_media_client")
            return
        }

        remoteMediaClient.load(request).setResultCallback { result ->
            val status = result.status
            Log.d(
                LOG_TAG,
                "cast action=load_result mode=stableHls success=${status.isSuccess} " +
                    "status=${status.statusCode} " +
                    "message=${status.statusMessage ?: ""} " +
                    "relay=$relayUrl",
            )
        }
        pendingLoad = false
        emitState(currentSession())
        log(
            "cast action=load mode=stableHls relay=$relayUrl " +
                "quality=${context.quality}",
        )
    }

    private fun startWebRtc(context: CastStreamContext) {
        activeCastMode = CastMode.LOW_LATENCY
        receiverLatencyMs = null
        receiverStatusMessage = null

        val session = currentSession()
        if (session?.isConnected != true) {
            log("cast action=webrtc_start_failed reason=missing_session")
            return
        }

        val webRtcTarget = webRtcTargetFor(context, session)
            ?: return
        sendWebRtcStartMessage(session, context, webRtcTarget)
    }

    private fun sendWebRtcStartMessage(
        session: CastSession,
        context: CastStreamContext,
        webRtcTarget: WebRtcTarget,
    ) {
        val config = context.config
        val message = JSONObject().apply {
            put("type", "startWebRtc")
            put("mode", "webrtc")
            put("channelLogin", webRtcTarget.channelLogin)
            put("title", context.title)
            context.subtitle
                ?.takeIf(String::isNotBlank)
                ?.let { subtitle -> put("subtitle", subtitle) }
            put("whepUrl", webRtcTarget.whepUrl)
            put("gatewayHostedOnPhone", webRtcTarget.gatewayHostedOnPhone)
            if (config.webRtcGatewayUrl.isNotBlank()) {
                put("gatewayUrl", config.webRtcGatewayUrl)
            }
        }.toString()

        session.sendMessage(CAST_NAMESPACE, message).setResultCallback { result ->
            val status = result.status
            if (!status.isSuccess) {
                receiverStatusMessage = "Unable to start WebRTC cast."
                emitState(session)
            }
            Log.d(
                LOG_TAG,
                "cast action=webrtc_start_result mode=lowLatency " +
                    "success=${status.isSuccess} status=${status.statusCode} " +
                    "message=${status.statusMessage ?: ""} " +
                    "gateway_hosted_on_phone=${webRtcTarget.gatewayHostedOnPhone} " +
                    "whep=${webRtcTarget.whepUrl.isNotBlank()}",
            )
        }
        pendingLoad = false
        emitState(session)
        log(
            "cast action=load mode=lowLatency channel=${context.channelLogin} " +
                "gateway_hosted_on_phone=${webRtcTarget.gatewayHostedOnPhone} " +
                "external_gateway=${config.webRtcGatewayUrl.isNotBlank()} " +
                "whep=${webRtcTarget.whepUrl.isNotBlank()}",
        )
    }

    private fun webRtcTargetFor(
        context: CastStreamContext,
        session: CastSession,
    ): WebRtcTarget? {
        val config = context.config
        val externalWhepUrl = config.externalWhepUrl
        if (externalWhepUrl.isNotBlank()) {
            stopPhoneWebRtcGateway()
            return WebRtcTarget(
                channelLogin = PhoneWebRtcGatewaySession.normalizeChannelLogin(context.channelLogin),
                whepUrl = externalWhepUrl,
                gatewayHostedOnPhone = false,
            )
        }

        val router = StreamProxySessionRegistry.routerFor(context.webViewIdentifier)
        if (router == null) {
            receiverStatusMessage = "Low Latency cast needs an active stream source."
            emitState(currentSession())
            log("cast action=webrtc_start_failed reason=missing_router")
            return null
        }

        val manifestUrl = router.latestUsherManifestUrl(context.channelLogin)
        if (manifestUrl == null) {
            receiverStatusMessage = "Low Latency cast needs an active stream source."
            emitState(currentSession())
            log("cast action=webrtc_start_failed reason=missing_manifest channel=${context.channelLogin}")
            return null
        }

        val relayUrl = relayServer.relayUrlFor(
            sourceUrl = manifestUrl,
            selectedQuality = context.quality,
        )
        val lanAddress = PhoneWebRtcGatewaySession.discoverLanIpv4Address()
        if (lanAddress == null) {
            receiverStatusMessage = "Low Latency cast needs a LAN IPv4 address."
            emitState(currentSession())
            log("cast action=webrtc_start_failed reason=missing_lan_ipv4")
            return null
        }

        val gatewaySession = runCatching {
            val gatewayPort = PhoneWebRtcGatewaySession.choosePort()
            val icePort = PhoneWebRtcGatewaySession.chooseIcePort(
                unavailablePorts = setOf(gatewayPort),
            )
            PhoneWebRtcGatewaySession.create(
                channelLogin = context.channelLogin,
                title = context.title,
                sourceUrl = relayUrl,
                lanAddress = lanAddress,
                port = gatewayPort,
                icePort = icePort,
            )
        }.onFailure { error ->
            receiverStatusMessage = "Unable to prepare Low Latency gateway."
            emitState(currentSession())
            log(
                "cast action=webrtc_start_failed reason=${error.javaClass.simpleName} " +
                    "message=${error.message}",
            )
        }.getOrNull() ?: return null

        startPhoneHostedWebRtcGateway(
            context = context,
            session = session,
            gatewaySession = gatewaySession,
        )
        return null
    }

    private fun startPhoneHostedWebRtcGateway(
        context: CastStreamContext,
        session: CastSession,
        gatewaySession: PhoneWebRtcGatewaySession,
    ) {
        phoneWebRtcGatewayRequestPath = gatewaySession.channelPath
        receiverStatusMessage = "Starting phone WebRTC gateway."
        emitState(session)

        runCatching {
            PhoneWebRtcGatewayService.start(applicationContext, gatewaySession) { result ->
                mainHandler.post {
                    handlePhoneHostedGatewayStartResult(
                        context = context,
                        gatewaySession = gatewaySession,
                        result = result,
                    )
                }
            }
        }.onFailure { error ->
            val gatewayAvailability = (error as? PhoneWebRtcGatewayUnavailableException)
                ?.availability
            receiverStatusMessage = gatewayAvailability?.userMessage
                ?: "Unable to start phone WebRTC gateway."
            phoneWebRtcGatewayActive = false
            phoneWebRtcGatewayRequestPath = null
            pendingLoad = false
            emitState(currentSession())
            log(
                "cast action=webrtc_start_failed " +
                    "reason=${gatewayAvailability?.reason ?: error.javaClass.simpleName} " +
                    "auto_fallback=${context.config.webRtcAutoFallback} " +
                    "message=${error.message} " +
                    "diagnostic=${gatewayAvailability?.diagnosticMessage ?: ""}",
            )
            if (context.config.webRtcAutoFallback) {
                loadStableHls(context)
            }
        }
    }

    private fun handlePhoneHostedGatewayStartResult(
        context: CastStreamContext,
        gatewaySession: PhoneWebRtcGatewaySession,
        result: PhoneWebRtcGatewayStartResult,
    ) {
        if (phoneWebRtcGatewayRequestPath != gatewaySession.channelPath) {
            log(
                "cast action=webrtc_start_ignored reason=stale_gateway " +
                    "channel=${gatewaySession.channelPath}",
            )
            return
        }

        val session = currentSession()
        if (session?.isConnected != true) {
            stopPhoneWebRtcGateway()
            log("cast action=webrtc_start_ignored reason=missing_session_after_gateway_start")
            return
        }

        if (!result.success) {
            receiverStatusMessage = result.userMessage.ifBlank {
                "Unable to start phone WebRTC gateway."
            }
            phoneWebRtcGatewayActive = false
            phoneWebRtcGatewayRequestPath = null
            pendingLoad = false
            emitState(session)
            log(
                "cast action=webrtc_start_failed reason=gateway_not_ready " +
                    "auto_fallback=${context.config.webRtcAutoFallback} " +
                    "diagnostic=${result.diagnosticMessage}",
            )
            if (context.config.webRtcAutoFallback) {
                loadStableHls(context)
            }
            return
        }

        phoneWebRtcGatewayActive = true
        receiverStatusMessage = null
        sendWebRtcStartMessage(
            session = session,
            context = context,
            webRtcTarget = WebRtcTarget(
                channelLogin = gatewaySession.channelPath,
                whepUrl = gatewaySession.whepUrl,
                gatewayHostedOnPhone = true,
            ),
        )
    }

    private fun updateRelay(context: CastStreamContext) {
        val router = StreamProxySessionRegistry.getOrCreateRouter(context.webViewIdentifier)
        relayServer.update(
            router = router,
            config = context.config,
        )
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

    private fun stopPhoneWebRtcGateway() {
        if (!phoneWebRtcGatewayActive && phoneWebRtcGatewayRequestPath == null) return

        phoneWebRtcGatewayActive = false
        phoneWebRtcGatewayRequestPath = null
        runCatching {
            PhoneWebRtcGatewayService.stop(applicationContext)
        }.onFailure { error ->
            log("phone_webrtc_gateway action=stop_failed reason=${error.javaClass.simpleName}")
        }
    }

    private fun currentSession(): CastSession? {
        return castContext?.sessionManager?.currentCastSession
    }

    private fun attachReceiverChannel(session: CastSession) {
        runCatching {
            session.setMessageReceivedCallbacks(CAST_NAMESPACE) { _, _, message ->
                val status = CastReceiverMessageParser.parse(message)
                    ?: return@setMessageReceivedCallbacks

                if (!status.appliesTo(activeCastMode)) {
                    logReceiverStatus(status)
                    return@setMessageReceivedCallbacks
                }

                receiverLatencyMs = status.latencyMs ?: receiverLatencyMs
                receiverStatusMessage = status.error
                    ?: status.playerState
                        ?.takeIf { state -> state.equals("failed", ignoreCase = true) }
                        ?.let { "Cast receiver reported failure." }
                logReceiverStatus(status)
                emitState(session)
            }
        }.onFailure { error ->
            log("cast action=receiver_channel_failed reason=${error.javaClass.simpleName}")
        }
    }

    private fun logReceiverStatus(status: CastReceiverStatus) {
        log(
            "cast action=receiver_status " +
                "mode=${status.mode ?: castModeLogName(activeCastMode)} " +
                "state=${status.playerState ?: ""} " +
                "error=${status.error ?: ""} " +
                "latency_ms=${status.latencyMs ?: -1} " +
                "current_sec=${status.currentTimeSec ?: -1.0} " +
                "range_start_sec=${status.rangeStartSec ?: -1.0} " +
                "range_end_sec=${status.rangeEndSec ?: -1.0} " +
                "target_sec=${status.targetLatencySec ?: -1.0} " +
                "max_sec=${status.maxLatencySec ?: -1.0} " +
                "playback_rate=${status.playbackRate ?: -1.0} " +
                "requested_rate=${status.requestedPlaybackRate ?: -1.0} " +
                "correction=${status.correction ?: ""} " +
                "latency_before_correction_ms=${status.latencyBeforeCorrectionMs ?: -1}",
        )
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
                "statusMessage" to receiverStatusMessage.takeIf { isCasting },
                "castMode" to castModeLogName(activeCastMode).takeIf { isCasting },
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
                "statusMessage" to null,
                "castMode" to null,
            ),
        )
    }

    private fun log(message: String) {
        if (streamContext?.config?.debugLogging == true) {
            Log.d(LOG_TAG, message)
        }
    }

    private inner class CastSessionListener : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {
            emitRoutes()
        }

        override fun onSessionStarted(session: CastSession, sessionId: String) {
            receiverLatencyMs = null
            receiverStatusMessage = null
            activeCastMode = streamContext?.config?.castMode ?: CastMode.STABLE_HLS
            connectingRouteId = null
            connectingRouteName = null
            startKeepAlive()
            attachReceiverChannel(session)
            emitState(session)
            emitRoutes()
            if (pendingLoad) {
                loadCurrent()
            }
        }

        override fun onSessionStartFailed(session: CastSession, error: Int) {
            pendingLoad = false
            receiverLatencyMs = null
            receiverStatusMessage = null
            activeCastMode = CastMode.STABLE_HLS
            connectingRouteId = null
            connectingRouteName = null
            stopPhoneWebRtcGateway()
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
            receiverLatencyMs = null
            receiverStatusMessage = null
            activeCastMode = CastMode.STABLE_HLS
            connectingRouteId = null
            connectingRouteName = null
            relayServer.close()
            stopPhoneWebRtcGateway()
            stopKeepAlive()
            emitDisconnected()
            emitRoutes()
            Log.d(
                LOG_TAG,
                "cast action=session_ended error=$error " +
                    "status=${castStatusName(error)} " +
                    "receiver=$receiverApplicationIdDescription",
            )
        }

        override fun onSessionResuming(session: CastSession, sessionId: String) = Unit

        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            receiverStatusMessage = null
            activeCastMode = streamContext?.config?.castMode ?: CastMode.STABLE_HLS
            connectingRouteId = null
            connectingRouteName = null
            startKeepAlive()
            attachReceiverChannel(session)
            emitState(session)
            emitRoutes()
            if (pendingLoad) {
                loadCurrent()
            }
        }

        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            receiverLatencyMs = null
            receiverStatusMessage = null
            activeCastMode = CastMode.STABLE_HLS
            connectingRouteId = null
            connectingRouteName = null
            stopPhoneWebRtcGateway()
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

        private fun castModeLogName(mode: CastMode): String {
            return when (mode) {
                CastMode.STABLE_HLS -> "stableHls"
                CastMode.LOW_LATENCY -> "lowLatency"
            }
        }

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
)

private data class WebRtcTarget(
    val channelLogin: String,
    val whepUrl: String,
    val gatewayHostedOnPhone: Boolean,
)
