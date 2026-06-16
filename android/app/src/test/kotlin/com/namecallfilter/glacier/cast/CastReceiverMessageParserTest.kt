package com.namecallfilter.glacier.cast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.namecallfilter.glacier.streamproxy.CastMode

class CastReceiverMessageParserTest {
    @Test
    fun parsesLatencyStatusMessage() {
        val status = CastReceiverMessageParser.parse(
            """{"type":"status","mode":"hls","latencyMs":7420,"playerState":"PLAYING","currentTimeSec":12.5,"rangeStartSec":3,"rangeEndSec":19.92,"targetLatencySec":1,"maxLatencySec":5,"playbackRate":1.075,"requestedPlaybackRate":1.075,"correction":"playbackRateCatchup","latencyBeforeCorrectionMs":6120}""",
        )

        assertEquals(7420L, status?.latencyMs)
        assertEquals("hls", status?.mode)
        assertEquals("PLAYING", status?.playerState)
        assertNull(status?.error)
        assertEquals(12.5, status?.currentTimeSec ?: 0.0, 0.001)
        assertEquals(3.0, status?.rangeStartSec ?: 0.0, 0.001)
        assertEquals(19.92, status?.rangeEndSec ?: 0.0, 0.001)
        assertEquals(1.0, status?.targetLatencySec ?: 0.0, 0.001)
        assertEquals(5.0, status?.maxLatencySec ?: 0.0, 0.001)
        assertEquals(1.075, status?.playbackRate ?: 0.0, 0.001)
        assertEquals(1.075, status?.requestedPlaybackRate ?: 0.0, 0.001)
        assertEquals("playbackRateCatchup", status?.correction)
        assertEquals(6120L, status?.latencyBeforeCorrectionMs)
    }

    @Test
    fun ignoresMalformedMessages() {
        assertNull(CastReceiverMessageParser.parse("not-json"))
        assertNull(CastReceiverMessageParser.parse("""{"type":"unknown"}"""))
    }

    @Test
    fun parsesWebRtcFailureMessage() {
        val status = CastReceiverMessageParser.parse(
            """{"type":"status","mode":"webrtc","playerState":"failed","error":"Missing WHEP URL"}""",
        )

        assertEquals("webrtc", status?.mode)
        assertEquals("failed", status?.playerState)
        assertEquals("Missing WHEP URL", status?.error)
    }

    @Test
    fun ignoresJsonNullAndStringNullStatusFields() {
        val jsonNullStatus = CastReceiverMessageParser.parse(
            """{"type":"status","mode":"webrtc","playerState":"connecting","error":null}""",
        )
        val stringNullStatus = CastReceiverMessageParser.parse(
            """{"type":"status","mode":"webrtc","playerState":"connecting","error":"null"}""",
        )

        assertEquals("connecting", jsonNullStatus?.playerState)
        assertNull(jsonNullStatus?.error)
        assertNull(stringNullStatus?.error)
    }

    @Test
    fun doesNotApplyHlsIdleStatusToLowLatencyCastState() {
        val status = CastReceiverMessageParser.parse(
            """{"type":"status","mode":"hls","playerState":"IDLE","error":null}""",
        )

        assertFalse(status!!.appliesTo(CastMode.LOW_LATENCY))
        assertTrue(status.appliesTo(CastMode.STABLE_HLS))
    }
}
