package com.namecallfilter.glacier.streamproxy

import java.net.URI
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

class StreamProxyRequestRouter(
    nowMs: () -> Long = { System.currentTimeMillis() },
    maxTrackedUrls: Int = DEFAULT_MAX_TRACKED_URLS,
    trackedUrlTtlMs: Long = DEFAULT_TRACKED_URL_TTL_MS,
    maxManifestUrls: Int = DEFAULT_MAX_MANIFEST_URLS,
    manifestUrlTtlMs: Long = DEFAULT_MANIFEST_URL_TTL_MS,
) {
    private val videoWeaverChannels = TtlLruMap<String, String>(
        maxEntries = maxTrackedUrls,
        ttlMs = trackedUrlTtlMs,
        nowMs = nowMs,
    )
    private val proxiedVideoWeaverUrls = TtlLruMap<String, Unit>(
        maxEntries = maxTrackedUrls,
        ttlMs = trackedUrlTtlMs,
        nowMs = nowMs,
    )
    private val usherManifestUrls = TtlLruMap<String, String>(
        maxEntries = maxManifestUrls,
        ttlMs = manifestUrlTtlMs,
        nowMs = nowMs,
    )
    private val usherChannelRegex = Regex("/hls/(.+)\\.m3u8", RegexOption.IGNORE_CASE)
    private val videoWeaverUrlRegex = Regex(
        "^https?://(?:[a-z0-9-]+\\.playlist\\.(?:live-video|ttvnw)\\.net|video-weaver\\.[a-z0-9-]+\\.hls\\.ttvnw\\.net)/v1/playlist/.+\\.m3u8(?:$|[?#])",
        RegexOption.IGNORE_CASE,
    )

    fun route(
        url: String,
        method: String,
        headers: Map<String, String>,
        config: StreamProxyConfig,
    ): StreamProxyDecision {
        if (!config.enabled) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.UNKNOWN,
                action = StreamProxyAction.DIRECT,
                reason = "mode_off",
            )
        }

        val uri = runCatching { URI(url) }.getOrNull()
            ?: return StreamProxyDecision(
                requestType = StreamProxyRequestType.UNKNOWN,
                action = StreamProxyAction.SKIP,
                reason = "invalid_url",
            )
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        val requestType = requestTypeForHost(host)
        val normalizedMethod = method.uppercase(Locale.US)
        val flagged = hasTtvLolProAcceptFlag(headers)

        if (requestType == StreamProxyRequestType.UNKNOWN && !flagged) {
            return StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "unknown",
            )
        }

        if (requestType == StreamProxyRequestType.GRAPHQL) {
            return StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "post_body_unavailable",
                flagged = flagged,
            )
        }

        if (normalizedMethod != "GET" && normalizedMethod != "HEAD") {
            return StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "method_not_supported",
                flagged = flagged,
            )
        }

        if (config.proxyUrls.isEmpty()) {
            return StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "no_proxy_urls",
                flagged = flagged,
            )
        }

        return when (requestType) {
            StreamProxyRequestType.USHER -> routeUsher(url, config, flagged)
            StreamProxyRequestType.VIDEO_WEAVER -> routeVideoWeaver(url, config, flagged)
            StreamProxyRequestType.PASSPORT,
            StreamProxyRequestType.TWITCH_WEBPAGE -> StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "optimized_unproxied",
                flagged = flagged,
            )
            StreamProxyRequestType.UNKNOWN -> StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "unknown",
                flagged = flagged,
            )
            StreamProxyRequestType.GRAPHQL -> StreamProxyDecision(
                requestType = requestType,
                action = StreamProxyAction.SKIP,
                reason = "post_body_unavailable",
                flagged = flagged,
            )
        }
    }

    fun rememberUsherManifest(channel: String?, manifestUrl: String, manifestBody: String) {
        val normalizedChannel = channel?.lowercase(Locale.US) ?: return
        val baseUri = runCatching { URI(manifestUrl) }.getOrNull() ?: return
        usherManifestUrls.put(normalizedChannel, manifestUrl)

        manifestBody
            .lineSequence()
            .map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { line ->
                runCatching { baseUri.resolve(line).toString() }.getOrNull()
            }
            .filter { videoWeaverUrlRegex.containsMatchIn(it) }
            .forEach { videoWeaverUrl ->
                videoWeaverChannels.put(videoWeaverUrl, normalizedChannel)
            }
    }

    fun rememberUsherRequest(url: String) {
        val channel = extractUsherChannel(url) ?: return
        usherManifestUrls.put(channel, url)
    }

    fun latestUsherManifestUrl(channel: String?): String? {
        val normalizedChannel = channel
            ?.trim()
            ?.lowercase(Locale.US)
            ?.takeIf(String::isNotEmpty)
            ?: return null

        return usherManifestUrls.get(normalizedChannel)
    }

    private fun routeUsher(
        url: String,
        config: StreamProxyConfig,
        flagged: Boolean,
    ): StreamProxyDecision {
        val channel = extractUsherChannel(url)

        if (url.contains("/vod/", ignoreCase = true)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.USHER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "vod",
                flagged = flagged,
            )
        }

        if (isFrontpageUsherUrl(url)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.USHER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "frontpage",
                flagged = flagged,
            )
        }

        if (!flagged) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.USHER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "optimized_unflagged",
                flagged = flagged,
            )
        }

        if (channel != null && config.whitelistedChannels.contains(channel)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.USHER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "whitelisted",
                flagged = flagged,
            )
        }

        return StreamProxyDecision(
            requestType = StreamProxyRequestType.USHER,
            action = StreamProxyAction.PROXY,
            channel = channel,
            flagged = flagged,
        )
    }

    private fun routeVideoWeaver(
        url: String,
        config: StreamProxyConfig,
        flagged: Boolean,
    ): StreamProxyDecision {
        val channel = videoWeaverChannels.get(url) ?: config.currentChannelLogin.takeIf(String::isNotEmpty)

        if (!isVideoWeaverPlaylistUrl(url)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.VIDEO_WEAVER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "not_playlist",
                flagged = flagged,
            )
        }

        if (!flagged) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.VIDEO_WEAVER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "optimized_unflagged",
                flagged = flagged,
            )
        }

        if (channel != null && config.whitelistedChannels.contains(channel)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.VIDEO_WEAVER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "whitelisted",
                flagged = flagged,
            )
        }

        if (!proxiedVideoWeaverUrls.putIfAbsent(url, Unit)) {
            return StreamProxyDecision(
                requestType = StreamProxyRequestType.VIDEO_WEAVER,
                action = StreamProxyAction.SKIP,
                channel = channel,
                reason = "optimized_already_proxied",
                flagged = flagged,
            )
        }

        return StreamProxyDecision(
            requestType = StreamProxyRequestType.VIDEO_WEAVER,
            action = StreamProxyAction.PROXY,
            channel = channel,
            flagged = flagged,
        )
    }

    private fun requestTypeForHost(host: String): StreamProxyRequestType {
        return when {
            host == "passport.twitch.tv" -> StreamProxyRequestType.PASSPORT
            host == "usher.ttvnw.net" -> StreamProxyRequestType.USHER
            isVideoWeaverHost(host) -> StreamProxyRequestType.VIDEO_WEAVER
            host == "gql.twitch.tv" -> StreamProxyRequestType.GRAPHQL
            host == "www.twitch.tv" || host == "m.twitch.tv" -> StreamProxyRequestType.TWITCH_WEBPAGE
            else -> StreamProxyRequestType.UNKNOWN
        }
    }

    private fun isVideoWeaverHost(host: String): Boolean {
        return Regex(
            "^(?:[a-z0-9-]+\\.playlist\\.(?:live-video|ttvnw)\\.net|video-weaver\\.[a-z0-9-]+\\.hls\\.ttvnw\\.net)$",
            RegexOption.IGNORE_CASE,
        ).matches(host)
    }

    private fun isVideoWeaverPlaylistUrl(url: String): Boolean {
        return videoWeaverUrlRegex.containsMatchIn(url)
    }

    private fun extractUsherChannel(url: String): String? {
        return usherChannelRegex
            .find(url)
            ?.groupValues
            ?.getOrNull(1)
            ?.lowercase(Locale.US)
    }

    private fun isFrontpageUsherUrl(url: String): Boolean {
        return url.contains("player_type=frontpage", ignoreCase = true) ||
            url.contains("%22player_type%22:%22frontpage%22", ignoreCase = true) ||
            url.contains("%22playerType%22:%22frontpage%22", ignoreCase = true)
    }

    private fun hasTtvLolProAcceptFlag(headers: Map<String, String>): Boolean {
        return headers.any { (name, value) ->
            name.equals("accept", ignoreCase = true) &&
                value.contains("TTV-LOL-PRO", ignoreCase = true)
        }
    }

    private class TtlLruMap<K, V>(
        private val maxEntries: Int,
        private val ttlMs: Long,
        private val nowMs: () -> Long,
    ) {
        private val entries = ConcurrentHashMap<K, Entry<V>>()

        fun put(key: K, value: V) {
            val now = nowMs()
            evict(now)
            entries[key] = Entry(
                value = value,
                createdMs = now,
                lastAccessMs = now,
            )
            evict(now)
        }

        fun putIfAbsent(key: K, value: V): Boolean {
            val now = nowMs()
            evict(now)
            val existing = entries[key]
            if (existing != null && !existing.isExpired(now, ttlMs)) {
                entries[key] = existing.copy(lastAccessMs = now)
                return false
            }

            entries[key] = Entry(
                value = value,
                createdMs = now,
                lastAccessMs = now,
            )
            evict(now)
            return true
        }

        fun get(key: K): V? {
            val now = nowMs()
            val existing = entries[key] ?: return null
            if (existing.isExpired(now, ttlMs)) {
                entries.remove(key, existing)
                return null
            }

            entries[key] = existing.copy(lastAccessMs = now)
            return existing.value
        }

        private fun evict(now: Long) {
            entries.entries.removeIf { entry -> entry.value.isExpired(now, ttlMs) }

            val limit = maxEntries.coerceAtLeast(0)
            val removeCount = entries.size - limit
            if (removeCount <= 0) return

            entries.entries
                .sortedWith(
                    compareBy<MutableMap.MutableEntry<K, Entry<V>>> {
                        it.value.lastAccessMs
                    }.thenBy { it.key.hashCode() },
                )
                .take(removeCount)
                .forEach { entry ->
                    entries.remove(entry.key, entry.value)
                }
        }

        private data class Entry<V>(
            val value: V,
            val createdMs: Long,
            val lastAccessMs: Long,
        ) {
            fun isExpired(nowMs: Long, ttlMs: Long): Boolean {
                return ttlMs >= 0L && nowMs - createdMs > ttlMs
            }
        }
    }

    private companion object {
        private const val DEFAULT_MAX_TRACKED_URLS = 512
        private const val DEFAULT_TRACKED_URL_TTL_MS = 10 * 60 * 1000L
        private const val DEFAULT_MAX_MANIFEST_URLS = 128
        private const val DEFAULT_MANIFEST_URL_TTL_MS = 6 * 60 * 60 * 1000L
    }
}
