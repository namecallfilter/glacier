package com.namecallfilter.glacier.castrelay

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

object CastRelayChannel {
    private const val CHANNEL_NAME = "frosty/cast_relay"
    private const val LOG_TAG = "FrostyCastRelay"

    fun register(flutterEngine: FlutterEngine) {
        val mainHandler = Handler(Looper.getMainLooper())
        val executor = Executors.newSingleThreadExecutor()
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )

        var debugLogging = false
        val server = CastRelayServer { message ->
            if (debugLogging) {
                Log.d(LOG_TAG, message)
            }
        }

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val config = config(call)
                    debugLogging = config.debugLogging
                    executor.execute {
                        val response = runCatching {
                            val port = server.start(config)
                            val host = CastRelayServer.lanAddress()
                                ?: throw IllegalStateException("No LAN address available")
                            mapOf("host" to host, "port" to port)
                        }
                        mainHandler.post {
                            response.fold(
                                onSuccess = { result.success(it) },
                                onFailure = { error ->
                                    result.error(
                                        "cast_relay_start_failed",
                                        error.message,
                                        error.javaClass.simpleName,
                                    )
                                },
                            )
                        }
                    }
                }
                "updateConfig" -> {
                    val config = config(call)
                    debugLogging = config.debugLogging
                    server.updateConfig(config)
                    result.success(null)
                }
                "resolveStreams" -> {
                    val url = (call.arguments as? Map<*, *>)?.get("url") as? String
                    if (url == null) {
                        result.error("missing_url", "Missing url", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        val response = runCatching {
                            val variants = server.resolveVariants(url)
                                ?: throw IllegalStateException("Master playlist fetch failed")
                            variants.map { variant ->
                                mapOf(
                                    "name" to variant.name,
                                    "resolution" to variant.resolution,
                                    "bandwidth" to variant.bandwidth,
                                    "frameRate" to variant.frameRate,
                                    "masterPath" to RelayUrls.masterPath(url),
                                    "mediaPath" to RelayUrls.mediaPath(variant.url),
                                )
                            }
                        }
                        mainHandler.post {
                            response.fold(
                                onSuccess = { result.success(it) },
                                onFailure = { error ->
                                    result.error(
                                        "cast_relay_resolve_failed",
                                        error.message,
                                        error.javaClass.simpleName,
                                    )
                                },
                            )
                        }
                    }
                }
                "stop" -> {
                    server.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun config(call: MethodCall): StreamProxyConfig {
        val arguments = call.arguments as? Map<*, *>
        return StreamProxyConfig.fromMap(arguments?.get("config") as? Map<*, *>)
    }
}
