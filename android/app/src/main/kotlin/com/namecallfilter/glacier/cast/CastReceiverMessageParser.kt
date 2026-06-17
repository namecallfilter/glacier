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
            targetLatencySec = doubleField(message, "targetLatencySec"),
            maxLatencySec = doubleField(message, "maxLatencySec"),
            latencyReference = stringField(message, "latencyReference"),
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
}

data class CastReceiverStatus(
    val latencyMs: Long?,
    val seekableLatencyMs: Long?,
    val currentTimeSec: Double?,
    val rangeStartSec: Double?,
    val rangeEndSec: Double?,
    val targetLatencySec: Double?,
    val maxLatencySec: Double?,
    val latencyReference: String?,
)
