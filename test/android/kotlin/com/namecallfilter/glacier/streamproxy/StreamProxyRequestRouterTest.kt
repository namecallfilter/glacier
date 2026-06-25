package com.namecallfilter.glacier.streamproxy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StreamProxyRequestRouterTest {
    @Test
    fun routesFlaggedUsherRequestsThroughProxy() {
        val router = StreamProxyRequestRouter()
        val decision = router.route(
            url = "https://usher.ttvnw.net/api/channel/hls/Streamer.m3u8?player_type=site",
            method = "GET",
            headers = mapOf("Accept" to "application/vnd.apple.mpegurl,TTV-LOL-PRO"),
            config = enabledConfig(),
        )

        assertEquals(StreamProxyRequestType.USHER, decision.requestType)
        assertEquals(StreamProxyAction.PROXY, decision.action)
        assertEquals("streamer", decision.channel)
    }

    @Test
    fun remembersLatestUsherManifestUrlFromManifestResponses() {
        val router = StreamProxyRequestRouter()
        val manifestUrl = "https://usher.ttvnw.net/api/channel/hls/Streamer.m3u8?token=abc"
        val manifestBody = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360
            https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8
        """.trimIndent()

        router.rememberUsherManifest(
            channel = "Streamer",
            manifestUrl = manifestUrl,
            manifestBody = manifestBody,
        )

        assertEquals(manifestUrl, router.latestUsherManifestUrl("streamer"))
    }

    @Test
    fun remembersLatestUsherManifestUrlFromObservedRequests() {
        val router = StreamProxyRequestRouter()
        val manifestUrl = "https://usher.ttvnw.net/api/channel/hls/Streamer.m3u8?token=abc"

        router.rememberUsherRequest(manifestUrl)

        assertEquals(manifestUrl, router.latestUsherManifestUrl("streamer"))
        assertNull(router.latestUsherManifestUrl("other_streamer"))
    }

    @Test
    fun expiresAlreadyProxiedVideoWeaverUrls() {
        var nowMs = 1_000L
        val router = StreamProxyRequestRouter(
            nowMs = { nowMs },
            maxTrackedUrls = 4,
            trackedUrlTtlMs = 1_000L,
        )
        val url = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8"
        val headers = mapOf("Accept" to "application/vnd.apple.mpegurl,TTV-LOL-PRO")

        val firstDecision = router.route(url, "GET", headers, enabledConfig())
        val secondDecision = router.route(url, "GET", headers, enabledConfig())
        nowMs += 1_001L
        val thirdDecision = router.route(url, "GET", headers, enabledConfig())

        assertEquals(StreamProxyAction.PROXY, firstDecision.action)
        assertEquals(StreamProxyAction.SKIP, secondDecision.action)
        assertEquals("optimized_already_proxied", secondDecision.reason)
        assertEquals(StreamProxyAction.PROXY, thirdDecision.action)
    }

    @Test
    fun boundsRememberedVideoWeaverChannelsWithLruEviction() {
        var nowMs = 1_000L
        val router = StreamProxyRequestRouter(
            nowMs = { nowMs },
            maxTrackedUrls = 2,
            trackedUrlTtlMs = 60_000L,
        )
        val firstUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/first.m3u8"
        val secondUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/second.m3u8"
        val thirdUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/third.m3u8"

        router.rememberUsherManifest("First", "https://usher.ttvnw.net/api/channel/hls/first.m3u8", manifest(firstUrl))
        nowMs += 1L
        router.rememberUsherManifest("Second", "https://usher.ttvnw.net/api/channel/hls/second.m3u8", manifest(secondUrl))
        nowMs += 1L
        router.rememberUsherManifest("Third", "https://usher.ttvnw.net/api/channel/hls/third.m3u8", manifest(thirdUrl))

        val config = enabledConfig().copy(currentChannelLogin = "")
        val headers = mapOf("Accept" to "application/vnd.apple.mpegurl,TTV-LOL-PRO")
        val evictedDecision = router.route(firstUrl, "GET", headers, config)
        val retainedDecision = router.route(secondUrl, "GET", headers, config)

        assertNull(evictedDecision.channel)
        assertEquals("second", retainedDecision.channel)
    }

    @Test
    fun expiresRememberedUsherManifestUrls() {
        var nowMs = 1_000L
        val router = StreamProxyRequestRouter(
            nowMs = { nowMs },
            manifestUrlTtlMs = 1_000L,
        )
        val manifestUrl = "https://usher.ttvnw.net/api/channel/hls/Streamer.m3u8?token=abc"

        router.rememberUsherRequest(manifestUrl)
        assertEquals(manifestUrl, router.latestUsherManifestUrl("streamer"))

        nowMs += 1_001L
        assertNull(router.latestUsherManifestUrl("streamer"))
    }

    private fun enabledConfig() = StreamProxyConfig(
        mode = StreamProxyMode.TTV_LOL_PRO,
        currentChannelLogin = "streamer",
        proxyUrls = listOf("proxy.example.com:3128"),
        whitelistedChannels = emptySet(),
        debugLogging = false,
    )

    private fun manifest(videoWeaverUrl: String): String {
        return """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360
            $videoWeaverUrl
        """.trimIndent()
    }
}
