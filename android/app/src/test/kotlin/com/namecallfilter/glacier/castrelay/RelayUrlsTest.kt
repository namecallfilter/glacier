package com.namecallfilter.glacier.castrelay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RelayUrlsTest {
    @Test
    fun `encodes and decodes upstream urls`() {
        val url = "https://usher.ttvnw.net/api/channel/hls/somechannel.m3u8?token={\"a\":1}&sig=x"

        assertEquals(url, RelayUrls.decodeSrc(RelayUrls.encodeSrc(url)))
    }

    @Test
    fun `decode rejects invalid base64`() {
        assertNull(RelayUrls.decodeSrc("not base64!!"))
    }

    @Test
    fun `builds relay paths`() {
        val url = "https://example.com/playlist.m3u8"
        val encoded = RelayUrls.encodeSrc(url)

        assertEquals("/master.m3u8?src=$encoded", RelayUrls.masterPath(url))
        assertEquals("/media.m3u8?src=$encoded", RelayUrls.mediaPath(url))
        assertEquals("/segment?src=$encoded", RelayUrls.segmentPath(url))
    }

    @Test
    fun `parses request targets`() {
        val (path, query) = RelayUrls.parseRequestTarget("/media.m3u8?src=abc&x=1%202")

        assertEquals("/media.m3u8", path)
        assertEquals("abc", query["src"])
        assertEquals("1 2", query["x"])

        val (bare, emptyQuery) = RelayUrls.parseRequestTarget("/segment")
        assertEquals("/segment", bare)
        assertEquals(emptyMap<String, String>(), emptyQuery)
    }
}
