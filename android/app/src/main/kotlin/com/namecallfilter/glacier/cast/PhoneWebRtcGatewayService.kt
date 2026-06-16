package com.namecallfilter.glacier.cast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import com.namecallfilter.glacier.R
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

data class PhoneWebRtcGatewayStartResult(
    val success: Boolean,
    val userMessage: String = "",
    val diagnosticMessage: String = "",
)

class PhoneWebRtcGatewayService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var gatewayProcess: MediaMtxGatewayProcess? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val session = intent?.toGatewaySession()
        if (session == null) {
            Log.d(LOG_TAG, "phone_webrtc_gateway action=start_failed reason=missing_session")
            completeStart(
                requestId = intent?.getStringExtra(EXTRA_REQUEST_ID),
                result = PhoneWebRtcGatewayStartResult(
                    success = false,
                    userMessage = "Unable to start phone WebRTC gateway.",
                    diagnosticMessage = "reason=missing_session",
                ),
            )
            stopSelf()
            return START_NOT_STICKY
        }
        val requestId = intent.getStringExtra(EXTRA_REQUEST_ID)

        startForegroundCompat(notificationText = "Starting local WebRTC gateway")
        acquireLocks()

        Thread {
            val startResult = runCatching {
                val process = gatewayProcess ?: MediaMtxGatewayProcess(
                    context = applicationContext,
                    log = ::log,
                ).also { gatewayProcess = it }
                process.start(session)
            }

            startResult.onSuccess {
                updateNotification("Serving ${session.channelPath} at ${session.whepUrl}")
                log(
                    "phone_webrtc_gateway action=started channel=${session.channelPath} " +
                        "bind=${session.bindAddress}:${session.port} ice=${session.icePort} " +
                        "whep=${session.whepUrl} " +
                        "source=${session.sourceUrl}",
                )
                completeStart(
                    requestId = requestId,
                    result = PhoneWebRtcGatewayStartResult(success = true),
                )
            }.onFailure { error ->
                releaseLocks()
                updateNotification("Local WebRTC gateway failed to start")
                val diagnosticMessage = if (error is MediaMtxGatewayStartException) {
                    error.diagnosticMessage
                } else {
                    "reason=${error.javaClass.simpleName} message=${error.message}"
                }
                Log.d(
                    LOG_TAG,
                    "phone_webrtc_gateway action=start_failed $diagnosticMessage",
                    error,
                )
                completeStart(
                    requestId = requestId,
                    result = PhoneWebRtcGatewayStartResult(
                        success = false,
                        userMessage = "Unable to start phone WebRTC gateway.",
                        diagnosticMessage = diagnosticMessage,
                    ),
                )
                stopSelf(startId)
            }
        }.apply {
            isDaemon = true
            name = "GlacierPhoneWebRtcGatewayStart"
            start()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        gatewayProcess?.stop()
        gatewayProcess = null
        releaseLocks()
        Log.d(LOG_TAG, "phone_webrtc_gateway action=stopped")
        super.onDestroy()
    }

    private fun startForegroundCompat(notificationText: String) {
        createNotificationChannel()
        val notification = notification(notificationText)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Phone WebRTC gateway",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Runs the local WebRTC gateway while Low Latency casting is active"
            setShowBadge(false)
        }

        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun updateNotification(text: String) {
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification(text))
    }

    private fun notification(text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Glacier Low Latency cast")
            .setContentText(text)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun acquireLocks() {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        if (wakeLock?.isHeld != true) {
            wakeLock = powerManager
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Glacier:PhoneWebRtcGatewayWakeLock")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }

        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        if (wifiLock?.isHeld != true) {
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                @Suppress("DEPRECATION")
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wifiManager
                .createWifiLock(mode, "Glacier:PhoneWebRtcGatewayWifiLock")
                .apply {
                    setReferenceCounted(false)
                    acquire()
                }
        }
    }

    private fun releaseLocks() {
        wakeLock
            ?.takeIf(PowerManager.WakeLock::isHeld)
            ?.release()
        wakeLock = null

        wifiLock
            ?.takeIf(WifiManager.WifiLock::isHeld)
            ?.release()
        wifiLock = null
    }

    private fun Intent.toGatewaySession(): PhoneWebRtcGatewaySession? {
        val channelPath = getStringExtra(EXTRA_CHANNEL_PATH) ?: return null
        val title = getStringExtra(EXTRA_TITLE).orEmpty()
        val sourceUrl = getStringExtra(EXTRA_SOURCE_URL) ?: return null
        val lanAddress = getStringExtra(EXTRA_LAN_ADDRESS) ?: return null
        val port = getIntExtra(EXTRA_PORT, -1)
            .takeIf { value -> value > 0 }
            ?: return null
        val icePort = getIntExtra(EXTRA_ICE_PORT, -1)
            .takeIf { value -> value > 0 }
            ?: return null

        return PhoneWebRtcGatewaySession.fromChannelPath(
            channelPath = channelPath,
            title = title,
            sourceUrl = sourceUrl,
            lanAddress = lanAddress,
            port = port,
            icePort = icePort,
        )
    }

    private fun log(message: String) {
        Log.d(LOG_TAG, message)
    }

    companion object {
        private const val ACTION_START = "com.namecallfilter.glacier.cast.START_PHONE_WEBRTC_GATEWAY"
        private const val ACTION_STOP = "com.namecallfilter.glacier.cast.STOP_PHONE_WEBRTC_GATEWAY"
        private const val EXTRA_CHANNEL_PATH = "channelPath"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SOURCE_URL = "sourceUrl"
        private const val EXTRA_LAN_ADDRESS = "lanAddress"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_ICE_PORT = "icePort"
        private const val EXTRA_REQUEST_ID = "requestId"
        private const val CHANNEL_ID = "glacier_phone_webrtc_gateway"
        private const val NOTIFICATION_ID = 5313
        private const val LOG_TAG = "GlacierCast"
        private val startCallbacks =
            ConcurrentHashMap<String, (PhoneWebRtcGatewayStartResult) -> Unit>()

        fun start(
            context: Context,
            session: PhoneWebRtcGatewaySession,
            onResult: (PhoneWebRtcGatewayStartResult) -> Unit,
        ) {
            runCatching {
                PhoneWebRtcGatewayBinary.requireAvailable(context)
            }.onFailure { error ->
                if (error is PhoneWebRtcGatewayUnavailableException) {
                    Log.d(
                        LOG_TAG,
                        "phone_webrtc_gateway action=preflight_failed " +
                            "reason=${error.availability.reason} " +
                            error.availability.diagnosticMessage,
                        error,
                    )
                }
                throw error
            }

            val requestId = UUID.randomUUID().toString()
            startCallbacks[requestId] = onResult

            val intent = Intent(context, PhoneWebRtcGatewayService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_CHANNEL_PATH, session.channelPath)
                .putExtra(EXTRA_TITLE, session.title)
                .putExtra(EXTRA_SOURCE_URL, session.sourceUrl)
                .putExtra(EXTRA_LAN_ADDRESS, session.lanAddress)
                .putExtra(EXTRA_PORT, session.port)
                .putExtra(EXTRA_ICE_PORT, session.icePort)
                .putExtra(EXTRA_REQUEST_ID, requestId)

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: RuntimeException) {
                startCallbacks.remove(requestId)
                throw error
            }
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, PhoneWebRtcGatewayService::class.java)
                    .setAction(ACTION_STOP),
            )
        }

        private fun completeStart(
            requestId: String?,
            result: PhoneWebRtcGatewayStartResult,
        ) {
            if (requestId == null) return

            startCallbacks
                .remove(requestId)
                ?.invoke(result)
        }
    }
}

private class MediaMtxGatewayStartException(
    message: String,
    val diagnosticMessage: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

private class MediaMtxGatewayProcess(
    private val context: Context,
    private val log: (String) -> Unit,
) {
    private var process: Process? = null
    private val outputLines = mutableListOf<String>()

    fun start(session: PhoneWebRtcGatewaySession) {
        stop()

        val workDir = File(context.filesDir, "phone_webrtc_gateway").apply {
            mkdirs()
        }
        val configFile = File(workDir, "${session.channelPath}.yml")
        configFile.writeText(session.mediaMtxConfig, StandardCharsets.UTF_8)

        val binary = PhoneWebRtcGatewayBinary.requireAvailable(context)
        log(
            "phone_webrtc_gateway action=process_starting binary=${binary.path} " +
                "supported_abis=${Build.SUPPORTED_ABIS.joinToString(",")} " +
                "config=${configFile.absolutePath}",
        )

        process = ProcessBuilder(binary.path, configFile.absolutePath)
            .directory(workDir)
            .redirectErrorStream(true)
            .start()
            .also { startedProcess ->
                Thread {
                    MediaMtxGatewayOutputPump.pump(
                        inputStream = startedProcess.inputStream,
                        rememberOutput = ::rememberOutput,
                        log = log,
                    )
                }.apply {
                    isDaemon = true
                    name = "GlacierMediaMtxLog"
                    start()
                }
            }

        waitUntilReachable(session)
    }

    fun stop() {
        val currentProcess = process ?: return
        process = null
        currentProcess.destroy()
        if (!currentProcess.waitFor(2, TimeUnit.SECONDS)) {
            currentProcess.destroyForcibly()
        }
    }

    private fun waitUntilReachable(session: PhoneWebRtcGatewaySession) {
        val deadlineMs = System.currentTimeMillis() + STARTUP_TIMEOUT_MS
        val probeUrl = "http://127.0.0.1:${session.port}/"

        while (System.currentTimeMillis() < deadlineMs) {
            val currentProcess = process
                ?: throw startException(
                    message = "MediaMTX process disappeared before startup completed",
                    reason = "missing_process",
                )
            if (!currentProcess.isAlive) {
                throw startException(
                    message = "MediaMTX exited before WebRTC endpoint became reachable",
                    reason = "process_exited",
                    exitCode = currentProcess.exitValue(),
                )
            }

            val statusCode = runCatching {
                val connection = URL(probeUrl).openConnection() as HttpURLConnection
                connection.connectTimeout = PROBE_TIMEOUT_MS
                connection.readTimeout = PROBE_TIMEOUT_MS
                connection.requestMethod = "GET"
                try {
                    connection.responseCode
                } finally {
                    connection.disconnect()
                }
            }.getOrNull()

            if (statusCode != null) {
                log(
                    "phone_webrtc_gateway action=reachable " +
                        "url=$probeUrl status=$statusCode",
                )
                return
            }

            Thread.sleep(PROBE_INTERVAL_MS)
        }

        throw startException(
            message = "MediaMTX WebRTC endpoint did not become reachable",
            reason = "startup_timeout",
        )
    }

    private fun rememberOutput(line: String) {
        synchronized(outputLines) {
            outputLines.add(line)
            if (outputLines.size > MAX_OUTPUT_LINES) {
                outputLines.removeAt(0)
            }
        }
    }

    private fun recentOutput(): String {
        return synchronized(outputLines) {
            outputLines.joinToString(separator = "\n")
        }
    }

    private fun startException(
        message: String,
        reason: String,
        exitCode: Int? = null,
    ): MediaMtxGatewayStartException {
        val availability = PhoneWebRtcGatewayBinary.availability(context)
        return MediaMtxGatewayStartException(
            message = message,
            diagnosticMessage = buildString {
                append("reason=$reason ")
                append(availability.diagnosticMessage)
                append(" exit_code=${exitCode ?: ""}")
                append(" output=${recentOutput()}")
            },
        )
    }

    private companion object {
        private const val STARTUP_TIMEOUT_MS = 8000L
        private const val PROBE_INTERVAL_MS = 200L
        private const val PROBE_TIMEOUT_MS = 300
        private const val MAX_OUTPUT_LINES = 80
    }
}

object MediaMtxGatewayOutputPump {
    fun pump(
        inputStream: InputStream,
        rememberOutput: (String) -> Unit,
        log: (String) -> Unit,
    ) {
        try {
            inputStream
                .bufferedReader()
                .lineSequence()
                .forEach { line ->
                    rememberOutput(line)
                    log("phone_webrtc_gateway process=$line")
                }
        } catch (error: IOException) {
            log(
                "phone_webrtc_gateway action=log_stream_closed " +
                    "reason=${error.javaClass.simpleName} " +
                    "message=${error.message ?: ""}",
            )
        }
    }
}
