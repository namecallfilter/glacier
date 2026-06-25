package com.namecallfilter.glacier.streamproxy

import java.net.URI
import java.util.Locale
import kotlin.math.roundToInt

object HlsPlaylistRewriter {
    data class MasterPlaylist(
        val variants: List<Variant>,
    )

    data class Variant(
        val quality: String,
        val url: String,
        val streamInfoLine: String,
        val streamInfoIndex: Int,
        val uriIndex: Int,
        val bandwidth: Long?,
        val width: Int?,
        val height: Int?,
        val frameRate: Double?,
        val score: Double?,
    )

    data class RewriteResult(
        val body: String,
        val selectedQuality: String?,
        val mediaSequence: Long? = null,
        val discontinuitySequence: Long? = null,
        val segmentCount: Int? = null,
        val prefetchUrls: List<String> = emptyList(),
    )

    private data class RequestedVideoQuality(
        val height: Int,
        val frameRate: Int?,
    )

    private data class MediaPlaylistTrimResult(
        val lines: List<String>,
        val mediaSequence: Long?,
        val discontinuitySequence: Long?,
        val segmentCount: Int,
    )

    private data class MediaSegment(
        val sequenceOffset: Int,
        val lines: List<String>,
        val durationSeconds: Double,
        val activeKeyLine: String?,
        val activeMapLine: String?,
        val discontinuityCount: Int,
    )

    fun parseMasterPlaylist(body: String, baseUrl: String): MasterPlaylist {
        return MasterPlaylist(parseVariants(body.lines(), baseUrl))
    }

    fun rewritePlaylist(
        body: String,
        baseUrl: String,
        selectedQuality: String?,
        rewriteUrl: (String) -> String,
    ): RewriteResult {
        val lines = body.lines()
        val variants = parseVariants(lines, baseUrl)

        if (variants.isNotEmpty()) {
            return rewriteMasterPlaylist(
                lines = lines,
                variants = variants,
                selectedQuality = selectedQuality,
                rewriteUrl = rewriteUrl,
            )
        }

        val trimmed = trimMediaPlaylist(lines)
        val prefetchUrls = mediaPrefetchUrls(trimmed.lines, baseUrl)
        return RewriteResult(
            body = trimmed.lines
                .map { line -> rewriteMediaPlaylistLine(line, baseUrl, rewriteUrl) }
                .joinToString("\n"),
            selectedQuality = null,
            mediaSequence = trimmed.mediaSequence,
            discontinuitySequence = trimmed.discontinuitySequence,
            segmentCount = trimmed.segmentCount,
            prefetchUrls = prefetchUrls,
        )
    }

    private fun rewriteMasterPlaylist(
        lines: List<String>,
        variants: List<Variant>,
        selectedQuality: String?,
        rewriteUrl: (String) -> String,
    ): RewriteResult {
        val selectedVariant = selectVariant(variants, selectedQuality)
        val exposesAllVariants = exposesAllVariants(selectedQuality)
        val variantByStreamInfoIndex = variants.associateBy { it.streamInfoIndex }
        val output = mutableListOf<String>()
        var lineIndex = 0

        while (lineIndex < lines.size) {
            val variant = variantByStreamInfoIndex[lineIndex]
            if (variant == null) {
                output.add(lines[lineIndex])
                lineIndex += 1
                continue
            }

            if (exposesAllVariants || selectedVariant == variant) {
                output.add(variant.streamInfoLine)
                output.add(rewriteUrl(variant.url))
            }
            lineIndex = variant.uriIndex + 1
        }

        return RewriteResult(
            body = output.joinToString("\n"),
            selectedQuality = selectedVariant?.quality,
        )
    }

    private fun trimMediaPlaylist(lines: List<String>): MediaPlaylistTrimResult {
        val headerLines = mutableListOf<String>()
        val segments = mutableListOf<MediaSegment>()
        val pendingSegmentLines = mutableListOf<String>()
        var activeKeyLine: String? = null
        var activeMapLine: String? = null
        var mediaSequence = 0L
        var discontinuitySequence = 0L
        var targetDurationSeconds: Double? = null
        var sawMediaSequence = false
        var sawDiscontinuitySequence = false
        var sawSegment = false

        fun addHeaderLine(line: String) {
            val trimmed = line.trim()
            when {
                isMediaSequenceLine(trimmed) -> {
                    mediaSequence = trimmed.substringAfter(":").trim().toLongOrNull() ?: 0L
                    sawMediaSequence = true
                }
                isDiscontinuitySequenceLine(trimmed) -> {
                    discontinuitySequence = trimmed.substringAfter(":").trim().toLongOrNull() ?: 0L
                    sawDiscontinuitySequence = true
                }
                isKeyLine(trimmed) -> activeKeyLine = line
                isMapLine(trimmed) -> activeMapLine = line
                else -> {
                    targetDurationSeconds = targetDurationSeconds
                        ?: targetDurationFromLine(trimmed)
                    headerLines += line
                }
            }
        }

        lines.forEach { line ->
            val trimmed = line.trim()
            when {
                !sawSegment &&
                    !isUriLine(trimmed) &&
                    !isSegmentScopedLine(trimmed) -> addHeaderLine(line)
                isKeyLine(trimmed) -> {
                    activeKeyLine = line
                    pendingSegmentLines += line
                }
                isMapLine(trimmed) -> {
                    activeMapLine = line
                    pendingSegmentLines += line
                }
                isUriLine(trimmed) -> {
                    pendingSegmentLines += line
                    segments += MediaSegment(
                        sequenceOffset = segments.size,
                        lines = pendingSegmentLines.toList(),
                        durationSeconds = segmentDurationSeconds(
                            lines = pendingSegmentLines,
                            fallbackDuration = targetDurationSeconds,
                        ),
                        activeKeyLine = activeKeyLine,
                        activeMapLine = activeMapLine,
                        discontinuityCount = pendingSegmentLines.count { pendingLine ->
                            isDiscontinuityLine(pendingLine.trim())
                        },
                    )
                    pendingSegmentLines.clear()
                    sawSegment = true
                }
                else -> pendingSegmentLines += line
            }
        }

        if (segments.isEmpty()) {
            return MediaPlaylistTrimResult(
                lines = lines,
                mediaSequence = mediaSequence.takeIf { sawMediaSequence },
                discontinuitySequence = discontinuitySequence.takeIf { sawDiscontinuitySequence },
                segmentCount = 0,
            )
        }

        val firstRetainedIndex = firstRetainedSegmentIndex(segments)
        val retainedSegments = segments.drop(firstRetainedIndex)
        val firstRetainedSegment = retainedSegments.first()
        val droppedDiscontinuityCount = segments
            .take(firstRetainedIndex)
            .sumOf(MediaSegment::discontinuityCount)
        val correctedMediaSequence = mediaSequence + firstRetainedSegment.sequenceOffset
        val correctedDiscontinuitySequence = discontinuitySequence + droppedDiscontinuityCount
        val output = mutableListOf<String>()

        appendHeaderWithSequences(
            output = output,
            headerLines = headerLines,
            mediaSequence = correctedMediaSequence,
            discontinuitySequence = correctedDiscontinuitySequence,
            includeDiscontinuitySequence = sawDiscontinuitySequence ||
                correctedDiscontinuitySequence > 0L,
        )

        if (
            firstRetainedSegment.activeKeyLine != null &&
            firstRetainedSegment.lines.none { line -> isKeyLine(line.trim()) }
        ) {
            output += firstRetainedSegment.activeKeyLine
        }
        if (
            firstRetainedSegment.activeMapLine != null &&
            firstRetainedSegment.lines.none { line -> isMapLine(line.trim()) }
        ) {
            output += firstRetainedSegment.activeMapLine
        }

        retainedSegments.forEach { segment ->
            output.addAll(segment.lines)
        }
        output.addAll(pendingSegmentLines)

        return MediaPlaylistTrimResult(
            lines = output,
            mediaSequence = correctedMediaSequence,
            discontinuitySequence = correctedDiscontinuitySequence,
            segmentCount = retainedSegments.size,
        )
    }

    private fun appendHeaderWithSequences(
        output: MutableList<String>,
        headerLines: List<String>,
        mediaSequence: Long,
        discontinuitySequence: Long,
        includeDiscontinuitySequence: Boolean,
    ) {
        var insertedSequences = false

        headerLines.forEachIndexed { index, line ->
            output += line
            if (!insertedSequences && line.trim().equals("#EXTM3U", ignoreCase = true)) {
                output += "#EXT-X-MEDIA-SEQUENCE:$mediaSequence"
                if (includeDiscontinuitySequence) {
                    output += "#EXT-X-DISCONTINUITY-SEQUENCE:$discontinuitySequence"
                }
                insertedSequences = true
            } else if (!insertedSequences && index == headerLines.lastIndex) {
                output += "#EXT-X-MEDIA-SEQUENCE:$mediaSequence"
                if (includeDiscontinuitySequence) {
                    output += "#EXT-X-DISCONTINUITY-SEQUENCE:$discontinuitySequence"
                }
                insertedSequences = true
            }
        }

        if (!insertedSequences) {
            output += "#EXT-X-MEDIA-SEQUENCE:$mediaSequence"
            if (includeDiscontinuitySequence) {
                output += "#EXT-X-DISCONTINUITY-SEQUENCE:$discontinuitySequence"
            }
        }
    }

    private fun firstRetainedSegmentIndex(segments: List<MediaSegment>): Int {
        var retainedDuration = 0.0
        var firstRetainedIndex = segments.lastIndex

        for (index in segments.lastIndex downTo 0) {
            val duration = segments[index].durationSeconds.coerceAtLeast(0.0)
            val nextDuration = retainedDuration + duration
            if (retainedDuration > 0.0 && nextDuration > MEDIA_PLAYLIST_WINDOW_SECONDS) {
                break
            }

            retainedDuration = nextDuration
            firstRetainedIndex = index
        }

        return firstRetainedIndex
    }

    private fun segmentDurationSeconds(
        lines: List<String>,
        fallbackDuration: Double?,
    ): Double {
        return lines
            .firstNotNullOfOrNull { line ->
                val trimmed = line.trim()
                if (!trimmed.startsWith("#EXTINF:", ignoreCase = true)) {
                    return@firstNotNullOfOrNull null
                }

                trimmed
                    .substringAfter(":")
                    .substringBefore(",")
                    .trim()
                    .toDoubleOrNull()
            }
            ?: fallbackDuration
            ?: 0.0
    }

    private fun targetDurationFromLine(line: String): Double? {
        if (!line.startsWith("#EXT-X-TARGETDURATION:", ignoreCase = true)) return null

        return line.substringAfter(":").trim().toDoubleOrNull()
    }

    private fun selectVariant(
        variants: List<Variant>,
        selectedQuality: String?,
    ): Variant? {
        val normalizedQuality = selectedQuality
            ?.trim()
            ?.lowercase(Locale.US)
            ?.takeIf(String::isNotEmpty)

        return when (normalizedQuality) {
            null,
            "auto" -> null
            "highest",
            "source" -> highestVariant(variants)
            else -> selectNamedVariant(variants, normalizedQuality)
        }
    }

    private fun exposesAllVariants(selectedQuality: String?): Boolean {
        val normalizedQuality = selectedQuality
            ?.trim()
            ?.lowercase(Locale.US)
            ?.takeIf(String::isNotEmpty)

        return normalizedQuality == null || normalizedQuality == "auto"
    }

    private fun selectNamedVariant(
        variants: List<Variant>,
        normalizedQuality: String,
    ): Variant? {
        variants.firstOrNull {
            it.quality.lowercase(Locale.US) == normalizedQuality
        }?.let { return it }

        requestedVideoQuality(normalizedQuality)?.let { requestedQuality ->
            variants
                .filter { variant ->
                    variant.height == requestedQuality.height &&
                        (
                            requestedQuality.frameRate == null ||
                                variant.frameRate?.roundToInt() == requestedQuality.frameRate
                        )
                }
                .maxWithOrNull(variantPreferenceComparator)
                ?.let { return it }
        }

        val requestedQualityKey = qualityTextKey(normalizedQuality)
        return variants.firstOrNull {
            qualityTextKey(it.quality) == requestedQualityKey
        }
    }

    private fun requestedVideoQuality(value: String): RequestedVideoQuality? {
        val match = requestedVideoQualityRegex.find(value) ?: return null
        val height = match.groupValues[1].toIntOrNull() ?: return null
        val frameRate = match.groupValues
            .getOrNull(2)
            ?.takeIf(String::isNotEmpty)
            ?.toIntOrNull()

        return RequestedVideoQuality(
            height = height,
            frameRate = frameRate,
        )
    }

    private fun highestVariant(variants: List<Variant>): Variant? {
        return variants.maxWithOrNull(variantPreferenceComparator)
    }

    private fun qualityTextKey(value: String): String {
        return value.lowercase(Locale.US).filter(Char::isLetterOrDigit)
    }

    private fun rewriteMediaPlaylistLine(
        line: String,
        baseUrl: String,
        rewriteUrl: (String) -> String,
    ): String {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return line

        if (trimmed.startsWith("#")) {
            return uriAttributeRegex.replace(line) { match ->
                val originalUrl = match.groupValues[1]
                "URI=\"${rewriteUrl(resolveUrl(baseUrl, originalUrl))}\""
            }
        }

        return rewriteUrl(resolveUrl(baseUrl, trimmed))
    }

    private fun mediaPrefetchUrls(lines: List<String>, baseUrl: String): List<String> {
        return lines.mapNotNull { line -> mediaPrefetchUrl(line, baseUrl) }
    }

    private fun mediaPrefetchUrl(line: String, baseUrl: String): String? {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) return null

        if (!trimmed.startsWith("#")) {
            return resolveUrl(baseUrl, trimmed)
        }

        if (
            trimmed.startsWith("#EXT-X-PART:", ignoreCase = true) ||
            trimmed.startsWith("#EXT-X-PRELOAD-HINT:", ignoreCase = true)
        ) {
            return uriAttributeRegex.find(line)
                ?.groupValues
                ?.getOrNull(1)
                ?.let { originalUrl -> resolveUrl(baseUrl, originalUrl) }
        }

        return null
    }

    private fun isUriLine(trimmedLine: String): Boolean {
        return trimmedLine.isNotEmpty() && !trimmedLine.startsWith("#")
    }

    private fun isMediaSequenceLine(trimmedLine: String): Boolean {
        return trimmedLine.startsWith("#EXT-X-MEDIA-SEQUENCE:", ignoreCase = true)
    }

    private fun isDiscontinuitySequenceLine(trimmedLine: String): Boolean {
        return trimmedLine.startsWith("#EXT-X-DISCONTINUITY-SEQUENCE:", ignoreCase = true)
    }

    private fun isDiscontinuityLine(trimmedLine: String): Boolean {
        return trimmedLine.equals("#EXT-X-DISCONTINUITY", ignoreCase = true)
    }

    private fun isKeyLine(trimmedLine: String): Boolean {
        return trimmedLine.startsWith("#EXT-X-KEY:", ignoreCase = true)
    }

    private fun isMapLine(trimmedLine: String): Boolean {
        return trimmedLine.startsWith("#EXT-X-MAP:", ignoreCase = true)
    }

    private fun isSegmentScopedLine(trimmedLine: String): Boolean {
        return trimmedLine.startsWith("#EXTINF:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-PART:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-BYTERANGE:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-PROGRAM-DATE-TIME:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-DATERANGE:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-GAP", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-CUE", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-X-ASSET:", ignoreCase = true) ||
            trimmedLine.startsWith("#EXT-OATCLS", ignoreCase = true) ||
            isDiscontinuityLine(trimmedLine)
    }

    private fun parseVariants(lines: List<String>, baseUrl: String): List<Variant> {
        val variants = mutableListOf<Variant>()
        var lineIndex = 0

        while (lineIndex < lines.size) {
            val line = lines[lineIndex].trim()
            if (!line.startsWith("#EXT-X-STREAM-INF:", ignoreCase = true)) {
                lineIndex += 1
                continue
            }

            val uriIndex = nextUriLineIndex(lines, lineIndex + 1)
            if (uriIndex == null) {
                lineIndex += 1
                continue
            }

            val attributes = parseAttributes(line.substringAfter(":"))
            val resolution = attributes["RESOLUTION"]
                ?.split("x", limit = 2)
                ?.mapNotNull { it.toIntOrNull() }
                ?.takeIf { it.size == 2 }
            val width = resolution?.getOrNull(0)
            val height = resolution?.getOrNull(1)
            val frameRate = attributes["FRAME-RATE"]?.toDoubleOrNull()
            val bandwidth = attributes["BANDWIDTH"]?.toLongOrNull()
            val score = attributes["SCORE"]?.toDoubleOrNull()

            variants += Variant(
                quality = qualityLabel(
                    height = height,
                    frameRate = frameRate,
                    bandwidth = bandwidth,
                    name = attributes["NAME"],
                ),
                url = resolveUrl(baseUrl, lines[uriIndex].trim()),
                streamInfoLine = lines[lineIndex],
                streamInfoIndex = lineIndex,
                uriIndex = uriIndex,
                bandwidth = bandwidth,
                width = width,
                height = height,
                frameRate = frameRate,
                score = score,
            )
            lineIndex = uriIndex + 1
        }

        return variants
    }

    private fun nextUriLineIndex(lines: List<String>, startIndex: Int): Int? {
        for (index in startIndex until lines.size) {
            val line = lines[index].trim()
            if (line.isEmpty()) continue
            if (!line.startsWith("#")) return index
            if (line.startsWith("#EXT-X-STREAM-INF:", ignoreCase = true)) return null
        }
        return null
    }

    private fun parseAttributes(value: String): Map<String, String> {
        return splitAttributeList(value).mapNotNull { attribute ->
            val separatorIndex = attribute.indexOf("=")
            if (separatorIndex <= 0) return@mapNotNull null

            val name = attribute.substring(0, separatorIndex).trim()
            val rawValue = attribute.substring(separatorIndex + 1).trim()
            name to rawValue.trim('"')
        }.toMap()
    }

    private fun splitAttributeList(value: String): List<String> {
        val attributes = mutableListOf<String>()
        val current = StringBuilder()
        var inQuotes = false

        value.forEach { char ->
            when (char) {
                '"' -> {
                    inQuotes = !inQuotes
                    current.append(char)
                }
                ',' -> {
                    if (inQuotes) {
                        current.append(char)
                    } else {
                        attributes += current.toString()
                        current.clear()
                    }
                }
                else -> current.append(char)
            }
        }

        if (current.isNotEmpty()) {
            attributes += current.toString()
        }

        return attributes
    }

    private fun qualityLabel(
        height: Int?,
        frameRate: Double?,
        bandwidth: Long?,
        name: String?,
    ): String {
        if (height != null) {
            val roundedFrameRate = frameRate?.roundToInt()
            return buildString {
                append(height)
                append("p")
                if (roundedFrameRate != null) {
                    append(roundedFrameRate)
                }
            }
        }

        if (!name.isNullOrBlank()) return name

        return bandwidth
            ?.let { "${it / 1000}k" }
            ?: "auto"
    }

    private fun resolveUrl(baseUrl: String, value: String): String {
        return runCatching { URI(baseUrl).resolve(value).toString() }
            .getOrDefault(value)
    }

    private const val MEDIA_PLAYLIST_WINDOW_SECONDS = 30.0

    private val uriAttributeRegex = Regex("""URI="([^"]+)"""")
    private val requestedVideoQualityRegex = Regex(
        """\b(\d{3,4})p(\d{2,3})?\b""",
        RegexOption.IGNORE_CASE,
    )
    private val variantPreferenceComparator = compareBy<Variant> { it.score ?: 0.0 }
        .thenBy { it.height ?: 0 }
        .thenBy { it.frameRate ?: 0.0 }
        .thenBy { it.bandwidth ?: 0L }
}
