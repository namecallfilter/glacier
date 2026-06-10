package com.namecallfilter.glacier.castrelay

import java.net.URI
import java.util.Locale

data class HlsVariant(
    val name: String,
    val resolution: String?,
    val bandwidth: Long,
    val frameRate: Double?,
    val url: String,
)

/**
 * Minimal HLS playlist parsing/rewriting for the Cast relay. Pure JVM so it is
 * unit-testable without Android.
 */
object HlsPlaylist {
    private const val STREAM_INF = "#EXT-X-STREAM-INF:"
    private const val MEDIA = "#EXT-X-MEDIA:"
    private const val TWITCH_PREFETCH = "#EXT-X-TWITCH-PREFETCH:"
    private val uriAttributeRegex = Regex("URI=\"([^\"]*)\"")
    private val rewrittenUriTags = listOf(
        "#EXT-X-MAP:",
        "#EXT-X-PART:",
        "#EXT-X-PRELOAD-HINT:",
        "#EXT-X-MEDIA:",
        "#EXT-X-I-FRAME-STREAM-INF:",
    )

    fun isMasterPlaylist(body: String): Boolean {
        return body.lineSequence().any { it.trim().startsWith(STREAM_INF) }
    }

    /** Parses the variant streams of a master playlist, resolved against [baseUrl]. */
    fun parseMaster(body: String, baseUrl: String): List<HlsVariant> {
        val mediaNamesByGroup = mutableMapOf<String, String>()
        body.lineSequence()
            .map(String::trim)
            .filter { it.startsWith(MEDIA) }
            .forEach { line ->
                val attributes = parseAttributes(line.removePrefix(MEDIA))
                val groupId = attributes["GROUP-ID"] ?: return@forEach
                val name = attributes["NAME"] ?: return@forEach
                mediaNamesByGroup[groupId] = name
            }

        val variants = mutableListOf<HlsVariant>()
        var pendingStreamInf: Map<String, String>? = null
        body.lineSequence().map(String::trim).forEach { line ->
            when {
                line.startsWith(STREAM_INF) -> {
                    pendingStreamInf = parseAttributes(line.removePrefix(STREAM_INF))
                }
                line.isNotEmpty() && !line.startsWith("#") -> {
                    val attributes = pendingStreamInf
                    pendingStreamInf = null
                    if (attributes != null) {
                        val resolution = attributes["RESOLUTION"]
                        val name = attributes["VIDEO"]?.let(mediaNamesByGroup::get)
                            ?: resolution
                            ?: "Variant ${variants.size + 1}"
                        variants += HlsVariant(
                            name = name,
                            resolution = resolution,
                            bandwidth = attributes["BANDWIDTH"]?.toLongOrNull() ?: 0L,
                            frameRate = attributes["FRAME-RATE"]?.toDoubleOrNull(),
                            url = resolveUrl(baseUrl, line),
                        )
                    }
                }
                else -> Unit
            }
        }
        return variants
    }

    /**
     * Rewrites every variant/rendition URL of a master playlist through
     * [mapUrl], which receives the absolute upstream URL.
     */
    fun rewriteMaster(body: String, baseUrl: String, mapUrl: (String) -> String): String {
        return rewriteLines(body, baseUrl, mapUrl)
    }

    /**
     * Rewrites every segment/part/map URL of a media playlist through
     * [mapUrl], including Twitch's prefetch hint tags.
     */
    fun rewriteMedia(body: String, baseUrl: String, mapUrl: (String) -> String): String {
        return rewriteLines(body, baseUrl, mapUrl)
    }

    /**
     * Selects a variant by name (e.g. "720p60"), falling back to the highest
     * bandwidth variant when [quality] is null or not found.
     */
    fun selectVariant(variants: List<HlsVariant>, quality: String?): HlsVariant? {
        if (variants.isEmpty()) return null

        if (quality != null) {
            val normalized = quality.trim().lowercase(Locale.US)
            variants.firstOrNull { it.name.trim().lowercase(Locale.US) == normalized }
                ?.let { return it }
            variants.firstOrNull {
                it.name.trim().lowercase(Locale.US).startsWith(normalized)
            }?.let { return it }
        }

        return variants.maxByOrNull(HlsVariant::bandwidth)
    }

    fun resolveUrl(baseUrl: String, reference: String): String {
        return runCatching { URI(baseUrl).resolve(reference.trim()).toString() }
            .getOrDefault(reference.trim())
    }

    private fun rewriteLines(
        body: String,
        baseUrl: String,
        mapUrl: (String) -> String,
    ): String {
        return body.lines().joinToString("\n") { rawLine ->
            val line = rawLine.trim()
            when {
                line.isEmpty() -> rawLine
                line.startsWith(TWITCH_PREFETCH) -> {
                    val url = line.removePrefix(TWITCH_PREFETCH)
                    TWITCH_PREFETCH + mapUrl(resolveUrl(baseUrl, url))
                }
                line.startsWith("#") -> {
                    if (rewrittenUriTags.any(line::startsWith)) {
                        rewriteUriAttribute(line, baseUrl, mapUrl)
                    } else {
                        rawLine
                    }
                }
                else -> mapUrl(resolveUrl(baseUrl, line))
            }
        }
    }

    private fun rewriteUriAttribute(
        line: String,
        baseUrl: String,
        mapUrl: (String) -> String,
    ): String {
        return uriAttributeRegex.replace(line) { match ->
            val original = match.groupValues[1]
            if (original.isEmpty()) {
                match.value
            } else {
                "URI=\"${mapUrl(resolveUrl(baseUrl, original))}\""
            }
        }
    }

    /** Parses HLS attribute lists, honoring quoted values containing commas. */
    fun parseAttributes(attributeList: String): Map<String, String> {
        val attributes = linkedMapOf<String, String>()
        var index = 0
        while (index < attributeList.length) {
            val equalsIndex = attributeList.indexOf('=', index)
            if (equalsIndex == -1) break

            val name = attributeList.substring(index, equalsIndex).trim().trimStart(',')
            var valueEnd: Int
            val value: String
            if (equalsIndex + 1 < attributeList.length &&
                attributeList[equalsIndex + 1] == '"'
            ) {
                val closingQuote = attributeList.indexOf('"', equalsIndex + 2)
                if (closingQuote == -1) break
                value = attributeList.substring(equalsIndex + 2, closingQuote)
                valueEnd = closingQuote + 1
            } else {
                val comma = attributeList.indexOf(',', equalsIndex + 1)
                valueEnd = if (comma == -1) attributeList.length else comma
                value = attributeList.substring(equalsIndex + 1, valueEnd).trim()
            }

            if (name.isNotEmpty()) {
                attributes[name] = value
            }
            index = if (valueEnd < attributeList.length &&
                attributeList[valueEnd] == ','
            ) {
                valueEnd + 1
            } else {
                valueEnd
            }
        }
        return attributes
    }
}
