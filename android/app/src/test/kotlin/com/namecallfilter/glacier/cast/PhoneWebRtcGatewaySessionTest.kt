package com.namecallfilter.glacier.cast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.DatagramSocket

class PhoneWebRtcGatewaySessionTest {
    @Test
    fun buildsPhoneHostedWhepUrlWithLanIpAndNormalizedChannelPath() {
        val session = PhoneWebRtcGatewaySession.create(
            channelLogin = " Shroud ",
            title = "shroud",
            sourceUrl = "http://192.168.5.42:53123/relay/source.m3u8",
            lanAddress = "192.168.5.42",
            port = 8889,
            icePort = 8190,
            sessionToken = "abc123",
        )

        assertEquals("shroud-abc123", session.channelPath)
        assertEquals("0.0.0.0", session.bindAddress)
        assertEquals(8190, session.icePort)
        assertEquals("http://192.168.5.42:8889/shroud-abc123/whep", session.whepUrl)
        assertTrue(session.gatewayHostedOnPhone)
    }

    @Test
    fun rehydratesExistingChannelPathWithoutAddingAnotherSessionToken() {
        val original = PhoneWebRtcGatewaySession.create(
            channelLogin = "jynxzi",
            title = "jynxzi",
            sourceUrl = "http://192.168.5.42:53123/relay/source.m3u8",
            lanAddress = "192.168.5.42",
            port = 8889,
            icePort = 8190,
            sessionToken = "dff6613864ed4660",
        )

        val rehydrated = PhoneWebRtcGatewaySession.fromChannelPath(
            channelPath = original.channelPath,
            title = original.title,
            sourceUrl = original.sourceUrl,
            lanAddress = original.lanAddress,
            port = original.port,
            icePort = original.icePort,
        )

        assertEquals("jynxzi-dff6613864ed4660", rehydrated.channelPath)
        assertEquals(original.whepUrl, rehydrated.whepUrl)
        assertEquals(original.mediaMtxConfig, rehydrated.mediaMtxConfig)
    }

    @Test
    fun generatedMediaMtxConfigBindsToAllInterfacesAndUsesOnDemandHlsSource() {
        val session = PhoneWebRtcGatewaySession.create(
            channelLogin = "Streamer_Name123",
            title = "Streamer_Name123",
            sourceUrl = "http://192.168.5.42:53123/relay/source.m3u8",
            lanAddress = "192.168.5.42",
            port = 8891,
            icePort = 8191,
            sessionToken = "token_456",
        )

        val config = session.mediaMtxConfig

        assertTrue(config.contains("api: false"))
        assertTrue(config.contains("metrics: false"))
        assertTrue(config.contains("pprof: false"))
        assertTrue(config.contains("playback: false"))
        assertTrue(config.contains("rtsp: false"))
        assertTrue(config.contains("rtmp: false"))
        assertTrue(config.contains("hls: false"))
        assertTrue(config.contains("srt: false"))
        assertTrue(config.contains("moq: false"))
        assertTrue(config.contains("webrtc: true"))
        assertTrue(config.contains("webrtcAddress: 0.0.0.0:8891"))
        assertTrue(config.contains("webrtcLocalUDPAddress: :8191"))
        assertTrue(config.contains("webrtcLocalTCPAddress: :8191"))
        assertTrue(config.contains("webrtcIPsFromInterfaces: false"))
        assertTrue(config.contains("webrtcAdditionalHosts: [192.168.5.42]"))
        assertTrue(config.contains("streamer_name123-token_456:"))
        assertTrue(config.contains("source: http://192.168.5.42:53123/relay/source.m3u8"))
        assertTrue(config.contains("sourceOnDemand: yes"))
        assertTrue(config.contains("sourceOnDemandStartTimeout: 45s"))
        assertTrue(config.contains("sourceOnDemandCloseAfter: 30s"))
    }

    @Test
    fun rejectsLoopbackAdvertisedAddressesBecauseChromecastCannotReachThem() {
        assertThrows(IllegalArgumentException::class.java) {
            PhoneWebRtcGatewaySession.create(
                channelLogin = "shroud",
                title = "shroud",
                sourceUrl = "http://192.168.5.42:53123/relay/source.m3u8",
                lanAddress = "127.0.0.1",
                port = 8889,
            )
        }
    }

    @Test
    fun choosesDifferentIcePortWhenPreferredUdpPortIsInUse() {
        DatagramSocket(0).use { occupiedSocket ->
            val occupiedPort = occupiedSocket.localPort

            val selectedPort = PhoneWebRtcGatewaySession.chooseIcePort(
                preferredPort = occupiedPort,
            )

            assertTrue(selectedPort in 1..65535)
            assertTrue(selectedPort != occupiedPort)
        }
    }
}
