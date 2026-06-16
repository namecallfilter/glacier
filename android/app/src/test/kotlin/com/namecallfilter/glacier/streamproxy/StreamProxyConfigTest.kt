package com.namecallfilter.glacier.streamproxy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamProxyConfigTest {
    @Test
    fun parsesCastSettingsFromMethodChannelPayload() {
        val config = StreamProxyConfig.fromMap(
            mapOf(
                "mode" to "ttvLolPro",
                "currentChannelLogin" to "Streamer",
                "proxyUrls" to listOf("proxy.example.com:3128"),
                "whitelistedChannels" to listOf("Whitelisted_Channel"),
                "castMode" to "lowLatency",
                "webRtcGatewayUrl" to " https://media.example.com ",
                "whepUrlOverride" to " https://media.example.com/streamer/whep ",
                "webRtcAutoFallback" to true,
                "debugLogging" to true,
            ),
        )

        assertEquals(StreamProxyMode.TTV_LOL_PRO, config.mode)
        assertEquals(CastMode.LOW_LATENCY, config.castMode)
        assertEquals("https://media.example.com", config.webRtcGatewayUrl)
        assertEquals("https://media.example.com/streamer/whep", config.whepUrlOverride)
        assertTrue(config.webRtcAutoFallback)
        assertTrue(config.debugLogging)
    }

    @Test
    fun defaultsCastSettingsToStableHls() {
        val config = StreamProxyConfig.fromMap(emptyMap<String, Any?>())

        assertEquals(CastMode.STABLE_HLS, config.castMode)
        assertEquals("", config.webRtcGatewayUrl)
        assertEquals("", config.whepUrlOverride)
        assertEquals(false, config.webRtcAutoFallback)
    }
}
