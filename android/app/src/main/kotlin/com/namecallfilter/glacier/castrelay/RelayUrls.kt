package com.namecallfilter.glacier.castrelay

import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * Relay endpoint paths and the upstream-URL encoding used in their `src`
 * query parameter. Pure JVM so it is unit-testable without Android.
 */
object RelayUrls {
    const val MASTER_PATH = "/master.m3u8"
    const val MEDIA_PATH = "/media.m3u8"
    const val SEGMENT_PATH = "/segment"

    fun encodeSrc(url: String): String {
        return Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(url.toByteArray(StandardCharsets.UTF_8))
    }

    fun decodeSrc(encoded: String): String? {
        return runCatching {
            String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8)
        }.getOrNull()
    }

    fun masterPath(upstreamUrl: String): String =
        "$MASTER_PATH?src=${encodeSrc(upstreamUrl)}"

    fun mediaPath(upstreamUrl: String): String =
        "$MEDIA_PATH?src=${encodeSrc(upstreamUrl)}"

    fun segmentPath(upstreamUrl: String): String =
        "$SEGMENT_PATH?src=${encodeSrc(upstreamUrl)}"

    /** Splits a request target like `/media.m3u8?src=abc` into path and query map. */
    fun parseRequestTarget(target: String): Pair<String, Map<String, String>> {
        val queryIndex = target.indexOf('?')
        if (queryIndex == -1) return target to emptyMap()

        val path = target.substring(0, queryIndex)
        val query = target.substring(queryIndex + 1)
            .split('&')
            .filter(String::isNotEmpty)
            .mapNotNull { pair ->
                val separator = pair.indexOf('=')
                if (separator == -1) return@mapNotNull null
                val name = pair.substring(0, separator)
                val value = runCatching {
                    URLDecoder.decode(pair.substring(separator + 1), "UTF-8")
                }.getOrNull() ?: return@mapNotNull null
                name to value
            }
            .toMap()
        return path to query
    }
}
