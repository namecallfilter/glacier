package com.namecallfilter.glacier.cast

object CastReceiverMessageParser {
    fun parse(message: String): CastReceiverStatus? {
        if (stringField(message, "type") != "status") return null

        val latencyMs = numberField(message, "latencyMs")
            ?.takeIf { it >= 0 }

        return CastReceiverStatus(
            latencyMs = latencyMs,
            seekableLatencyMs = numberField(message, "seekableLatencyMs")
                ?.takeIf { it >= 0 },
            currentTimeSec = doubleField(message, "currentTimeSec"),
            rangeStartSec = doubleField(message, "rangeStartSec"),
            rangeEndSec = doubleField(message, "rangeEndSec"),
            liveEdgeTimeSec = doubleField(message, "liveEdgeTimeSec"),
            targetLatencySec = doubleField(message, "targetLatencySec"),
            maxLatencySec = doubleField(message, "maxLatencySec"),
            latencyReference = stringField(message, "latencyReference"),
            buffering = booleanField(message, "buffering"),
            bufferingAgeMs = numberField(message, "bufferingAgeMs")
                ?.takeIf { it >= 0 },
            playerState = stringField(message, "playerState"),
            playbackRate = doubleField(message, "playbackRate"),
            receiverVersion = stringField(message, "receiverVersion"),
        )
    }

    fun parseDiagnostic(message: String): CastReceiverDiagnostic? {
        if (stringField(message, "type") != "diagnostic") return null

        val action = stringField(message, "action") ?: return null
        val fields = orderedFields(message)
            .filterNot { field ->
                field.key == "type" || field.key == "action"
            }
            .associate { field ->
                logKey(field.key) to field.value
            }

        return CastReceiverDiagnostic(
            action = action,
            fields = fields,
        )
    }

    private fun stringField(message: String, name: String): String? {
        return rawField(message, name)
            ?.takeIf { value -> !value.startsWith("{") && !value.startsWith("[") }
            ?.takeIf(String::isNotBlank)
    }

    private fun numberField(message: String, name: String): Long? {
        return rawField(message, name)?.toLongOrNull()
    }

    private fun doubleField(message: String, name: String): Double? {
        return rawField(message, name)?.toDoubleOrNull()
    }

    private fun booleanField(message: String, name: String): Boolean? {
        return when (rawField(message, name)?.lowercase()) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    private fun orderedFields(message: String): List<DiagnosticField> {
        return fieldRegex.findAll(message)
            .mapNotNull { match ->
                val key = match.groupValues.getOrNull(1) ?: return@mapNotNull null
                val rawValue = match.groupValues.getOrNull(2)
                    ?.trim()
                    ?: return@mapNotNull null
                val value = rawValue
                    .removeSurrounding("\"")
                    .takeIf(String::isNotBlank)
                    ?: return@mapNotNull null

                DiagnosticField(
                    key = key,
                    value = value,
                )
            }
            .toList()
    }

    private fun logKey(key: String): String {
        return key
            .replace(Regex("([a-z0-9])([A-Z])"), "$1_$2")
            .replace(Regex("[^A-Za-z0-9_]+"), "_")
            .trim('_')
            .lowercase()
    }

    private fun rawField(message: String, name: String): String? {
        val keyIndex = message.indexOf("\"$name\"")
        if (keyIndex < 0) return null

        val colonIndex = message.indexOf(":", startIndex = keyIndex + name.length + 2)
        if (colonIndex < 0) return null

        var valueIndex = colonIndex + 1
        while (valueIndex < message.length && message[valueIndex].isWhitespace()) {
            valueIndex += 1
        }
        if (valueIndex >= message.length) return null

        if (message[valueIndex] == '"') {
            val endIndex = message.indexOf('"', startIndex = valueIndex + 1)
            if (endIndex < 0) return null
            return message.substring(valueIndex + 1, endIndex)
        }

        val endIndex = message.indexOfAny(
            chars = charArrayOf(',', '}'),
            startIndex = valueIndex,
        ).takeIf { it >= 0 } ?: message.length

        return message.substring(valueIndex, endIndex).trim()
    }

    private data class DiagnosticField(
        val key: String,
        val value: String,
    )

    private val fieldRegex = Regex("\"([^\"]+)\"\\s*:\\s*(\"[^\"]*\"|[^,{}]+)")
}

data class CastReceiverStatus(
    val latencyMs: Long?,
    val seekableLatencyMs: Long?,
    val currentTimeSec: Double?,
    val rangeStartSec: Double?,
    val rangeEndSec: Double?,
    val liveEdgeTimeSec: Double?,
    val targetLatencySec: Double?,
    val maxLatencySec: Double?,
    val latencyReference: String?,
    val buffering: Boolean? = null,
    val bufferingAgeMs: Long? = null,
    val playerState: String? = null,
    val playbackRate: Double? = null,
    val receiverVersion: String? = null,
)

data class CastReceiverDiagnostic(
    val action: String,
    val fields: Map<String, String>,
)
