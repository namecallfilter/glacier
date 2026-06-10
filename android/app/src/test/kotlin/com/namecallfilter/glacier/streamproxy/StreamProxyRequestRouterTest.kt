package com.namecallfilter.glacier.streamproxy

import org.junit.Assert.assertEquals
import org.junit.Test

class StreamProxyRequestRouterTest {
    private val flaggedHeaders = mapOf("Accept" to "application/x-mpegURL, TTV-LOL-PRO")
    private val usherUrl =
        "https://usher.ttvnw.net/api/channel/hls/somechannel.m3u8?token=abc&sig=def"
    private val weaverUrl =
        "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/abc123.m3u8"

    private fun config(
        mode: StreamProxyMode = StreamProxyMode.TTV_LOL_PRO,
        proxyUrls: List<String> = listOf("http://proxy.example.com:8080"),
        whitelisted: Set<String> = emptySet(),
        currentChannel: String = "somechannel",
    ) = StreamProxyConfig(
        mode = mode,
        currentChannelLogin = currentChannel,
        proxyUrls = proxyUrls,
        whitelistedChannels = whitelisted,
        debugLogging = false,
    )

    @Test
    fun `mode off routes direct`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "GET",
            flaggedHeaders,
            config(mode = StreamProxyMode.OFF),
        )

        assertEquals(StreamProxyAction.DIRECT, decision.action)
        assertEquals("mode_off", decision.reason)
    }

    @Test
    fun `flagged usher request is proxied with extracted channel`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "GET",
            flaggedHeaders,
            config(),
        )

        assertEquals(StreamProxyAction.PROXY, decision.action)
        assertEquals(StreamProxyRequestType.USHER, decision.requestType)
        assertEquals("somechannel", decision.channel)
    }

    @Test
    fun `unflagged usher request is skipped`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "GET",
            mapOf("Accept" to "application/x-mpegURL"),
            config(),
        )

        assertEquals(StreamProxyAction.SKIP, decision.action)
        assertEquals("optimized_unflagged", decision.reason)
    }

    @Test
    fun `whitelisted channel is skipped`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "GET",
            flaggedHeaders,
            config(whitelisted = setOf("somechannel")),
        )

        assertEquals(StreamProxyAction.SKIP, decision.action)
        assertEquals("whitelisted", decision.reason)
    }

    @Test
    fun `vod and frontpage usher requests are skipped`() {
        val router = StreamProxyRequestRouter()

        val vod = router.route(
            "https://usher.ttvnw.net/vod/12345.m3u8",
            "GET",
            flaggedHeaders,
            config(),
        )
        assertEquals("vod", vod.reason)

        val frontpage = router.route(
            "$usherUrl&player_type=frontpage",
            "GET",
            flaggedHeaders,
            config(),
        )
        assertEquals("frontpage", frontpage.reason)
    }

    @Test
    fun `unknown hosts are skipped`() {
        val decision = StreamProxyRequestRouter().route(
            "https://example.cloudfront.net/segment1.ts",
            "GET",
            emptyMap(),
            config(),
        )

        assertEquals(StreamProxyAction.SKIP, decision.action)
        assertEquals(StreamProxyRequestType.UNKNOWN, decision.requestType)
    }

    @Test
    fun `no proxy urls skips`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "GET",
            flaggedHeaders,
            config(proxyUrls = emptyList()),
        )

        assertEquals(StreamProxyAction.SKIP, decision.action)
        assertEquals("no_proxy_urls", decision.reason)
    }

    @Test
    fun `non get methods are skipped`() {
        val decision = StreamProxyRequestRouter().route(
            usherUrl,
            "POST",
            flaggedHeaders,
            config(),
        )

        assertEquals(StreamProxyAction.SKIP, decision.action)
        assertEquals("method_not_supported", decision.reason)
    }

    @Test
    fun `video weaver playlist is proxied once then skipped`() {
        val router = StreamProxyRequestRouter()

        val first = router.route(weaverUrl, "GET", flaggedHeaders, config())
        assertEquals(StreamProxyAction.PROXY, first.action)
        assertEquals(StreamProxyRequestType.VIDEO_WEAVER, first.requestType)

        val second = router.route(weaverUrl, "GET", flaggedHeaders, config())
        assertEquals(StreamProxyAction.SKIP, second.action)
        assertEquals("optimized_already_proxied", second.reason)
    }

    @Test
    fun `remembered usher manifest maps weaver urls to their channel`() {
        val router = StreamProxyRequestRouter()
        router.rememberUsherManifest(
            channel = "OtherChannel",
            manifestUrl = usherUrl,
            manifestBody = """
                #EXTM3U
                #EXT-X-STREAM-INF:BANDWIDTH=6000000
                $weaverUrl
            """.trimIndent(),
        )

        val decision = router.route(
            weaverUrl,
            "GET",
            flaggedHeaders,
            config(currentChannel = ""),
        )

        assertEquals("otherchannel", decision.channel)
    }
}
