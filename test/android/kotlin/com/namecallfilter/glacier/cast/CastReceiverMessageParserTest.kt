package com.namecallfilter.glacier.cast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CastReceiverMessageParserTest {
    @Test
    fun parsesLatencyStatusMessage() {
        val status = CastReceiverMessageParser.parse(
            """{"type":"status","latencyMs":7420,"seekableLatencyMs":2410,"currentTimeSec":12.5,"rangeStartSec":3,"rangeEndSec":19.92,"liveEdgeTimeSec":22.1,"targetLatencySec":1,"maxLatencySec":5,"latencyReference":"absoluteLiveEdge","buffering":true,"bufferingAgeMs":1500,"playerState":"BUFFERING","playbackRate":1.05,"receiverVersion":"2026-06-24-1"}""",
        )

        assertEquals(7420L, status?.latencyMs)
        assertEquals(2410L, status?.seekableLatencyMs)
        assertEquals(12.5, status?.currentTimeSec ?: 0.0, 0.001)
        assertEquals(3.0, status?.rangeStartSec ?: 0.0, 0.001)
        assertEquals(19.92, status?.rangeEndSec ?: 0.0, 0.001)
        assertEquals(22.1, status?.liveEdgeTimeSec ?: 0.0, 0.001)
        assertEquals(1.0, status?.targetLatencySec ?: 0.0, 0.001)
        assertEquals(5.0, status?.maxLatencySec ?: 0.0, 0.001)
        assertEquals("absoluteLiveEdge", status?.latencyReference)
        assertEquals(true, status?.buffering)
        assertEquals(1500L, status?.bufferingAgeMs)
        assertEquals("BUFFERING", status?.playerState)
        assertEquals(1.05, status?.playbackRate ?: 0.0, 0.001)
        assertEquals("2026-06-24-1", status?.receiverVersion)
    }

    @Test
    fun parsesReceiverDiagnosticMessage() {
        val diagnostic = CastReceiverMessageParser.parseDiagnostic(
            """{"type":"diagnostic","action":"buffering","buffering":true,"currentLatencyMs":5772,"rangeEnd":852.814,"reason":"rebuffer"}""",
        )

        assertEquals("buffering", diagnostic?.action)
        assertEquals(
            "cast action=receiver_diagnostic receiver_action=buffering " +
                "buffering=true current_latency_ms=5772 range_end=852.814 reason=rebuffer",
            receiverDiagnosticLogLine(diagnostic!!),
        )
    }

    @Test
    fun formatsReceiverStatusLogLine() {
        val line = receiverStatusLogLine(
            CastReceiverStatus(
                latencyMs = 7420,
                seekableLatencyMs = 2410,
                currentTimeSec = 12.5,
                rangeStartSec = 3.0,
                rangeEndSec = 19.92,
                liveEdgeTimeSec = 22.1,
                targetLatencySec = 1.0,
                maxLatencySec = 5.0,
                latencyReference = "absoluteLiveEdge",
                buffering = true,
                bufferingAgeMs = 1500,
                playerState = "BUFFERING",
                playbackRate = 1.05,
                receiverVersion = "2026-06-24-1",
            ),
        )

        assertEquals(
            "cast action=receiver_status " +
                "latency_ms=7420 " +
                "seekable_latency_ms=2410 " +
                "current_sec=12.5 " +
                "range_start_sec=3.0 " +
                "range_end_sec=19.92 " +
                "live_edge_sec=22.1 " +
                "target_sec=1.0 " +
                "max_sec=5.0 " +
                "latency_reference=absoluteLiveEdge " +
                "buffering=true " +
                "buffering_age_ms=1500 " +
                "player_state=BUFFERING " +
                "playback_rate=1.05 " +
                "receiver_version=2026-06-24-1",
            line,
        )
    }

    @Test
    fun reportsReceiverRuntimeMismatchWhenHostedReceiverIsStale() {
        val line = receiverRuntimeMismatchLogLine(
            CastReceiverStatus(
                latencyMs = 7420,
                seekableLatencyMs = 2410,
                currentTimeSec = 12.5,
                rangeStartSec = 3.0,
                rangeEndSec = 19.92,
                liveEdgeTimeSec = 22.1,
                targetLatencySec = 1.0,
                maxLatencySec = 5.0,
                latencyReference = "absoluteLiveEdge",
            ),
        )

        assertEquals(
            "cast action=receiver_runtime_mismatch " +
                "expected_version=2026-06-24-1 " +
                "actual_version=missing " +
                "missing_fields=receiverVersion,buffering,playerState,playbackRate",
            line,
        )
    }

    @Test
    fun ignoresMalformedMessages() {
        assertNull(CastReceiverMessageParser.parse("not-json"))
        assertNull(CastReceiverMessageParser.parse("""{"type":"unknown"}"""))
    }
}
