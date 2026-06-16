package com.namecallfilter.glacier.streamproxy

import java.net.URI
import java.net.PasswordAuthentication
import java.util.Locale

enum class StreamProxyMode {
    OFF,
    TTV_LOL_PRO,
}

enum class CastMode {
    STABLE_HLS,
    LOW_LATENCY,
}

enum class StreamProxyRequestType(val logName: String) {
    PASSPORT("passport"),
    USHER("usher"),
    VIDEO_WEAVER("videoWeaver"),
    GRAPHQL("graphQL"),
    TWITCH_WEBPAGE("twitchWebpage"),
    UNKNOWN("unknown"),
}

enum class StreamProxyAction(val logName: String) {
    PROXY("proxy"),
    SKIP("skip"),
    DIRECT("direct"),
}

data class StreamProxyDecision(
    val requestType: StreamProxyRequestType,
    val action: StreamProxyAction,
    val channel: String? = null,
    val reason: String? = null,
    val flagged: Boolean = false,
)

data class StreamProxyConfig(
    val mode: StreamProxyMode,
    val currentChannelLogin: String,
    val proxyUrls: List<String>,
    val whitelistedChannels: Set<String>,
    val castMode: CastMode = CastMode.STABLE_HLS,
    val webRtcGatewayUrl: String = "",
    val whepUrlOverride: String = "",
    val webRtcAutoFallback: Boolean = false,
    val debugLogging: Boolean,
) {
    val enabled: Boolean
        get() = mode == StreamProxyMode.TTV_LOL_PRO

    val externalWhepUrl: String
        get() {
            if (whepUrlOverride.isNotBlank()) return whepUrlOverride
            if (webRtcGatewayUrl.isBlank() || currentChannelLogin.isBlank()) {
                return ""
            }

            val gateway = webRtcGatewayUrl.trim().trimEnd('/')
            return "$gateway/$currentChannelLogin/whep"
        }

    companion object {
        fun fromMap(map: Map<*, *>?): StreamProxyConfig {
            val mode = when (map?.get("mode") as? String) {
                "ttvLolPro" -> StreamProxyMode.TTV_LOL_PRO
                else -> StreamProxyMode.OFF
            }
            val castMode = when (map?.get("castMode") as? String) {
                "lowLatency" -> CastMode.LOW_LATENCY
                else -> CastMode.STABLE_HLS
            }

            return StreamProxyConfig(
                mode = mode,
                currentChannelLogin = (map?.get("currentChannelLogin") as? String)
                    ?.trim()
                    ?.lowercase(Locale.US)
                    .orEmpty(),
                proxyUrls = stringList(map, "proxyUrls"),
                whitelistedChannels = stringList(map, "whitelistedChannels")
                    .map { it.lowercase(Locale.US) }
                    .toSet(),
                castMode = castMode,
                webRtcGatewayUrl = stringValue(map, "webRtcGatewayUrl"),
                whepUrlOverride = stringValue(map, "whepUrlOverride"),
                webRtcAutoFallback = (map?.get("webRtcAutoFallback") as? Boolean) ?: false,
                debugLogging = (map?.get("debugLogging") as? Boolean) ?: false,
            )
        }

        private fun stringValue(map: Map<*, *>?, key: String): String {
            return (map?.get(key) as? String)
                ?.trim()
                .orEmpty()
        }

        private fun stringList(map: Map<*, *>?, key: String): List<String> {
            return (map?.get(key) as? List<*>)
                ?.mapNotNull { (it as? String)?.trim()?.takeIf(String::isNotEmpty) }
                ?: emptyList()
        }
    }
}

data class ParsedProxy(
    val scheme: String,
    val host: String,
    val port: Int,
    val username: String?,
    val password: String?,
) {
    val displayHost: String
        get() = "$host:$port"

    val hasCredentials: Boolean
        get() = username != null

    val passwordAuthentication: PasswordAuthentication?
        get() {
            val user = username ?: return null
            return PasswordAuthentication(user, (password ?: "").toCharArray())
        }
}

fun parseProxyUrl(rawUrl: String): ParsedProxy? {
    val trimmed = rawUrl.trim()
    if (trimmed.isEmpty()) return null

    val normalized = if (trimmed.contains("://")) trimmed else "http://$trimmed"
    val uri = runCatching { URI(normalized) }.getOrNull() ?: return null
    val scheme = uri.scheme?.lowercase(Locale.US) ?: return null
    if (scheme != "http" && scheme != "https") return null

    val host = uri.host?.takeIf(String::isNotEmpty) ?: return null
    val port = uri.port.takeIf { it in 1..65535 } ?: return null
    val credentials = uri.userInfo?.split(":", limit = 2)

    return ParsedProxy(
        scheme = scheme,
        host = host,
        port = port,
        username = credentials?.getOrNull(0),
        password = credentials?.getOrNull(1),
    )
}
