package com.namecallfilter.glacier.castrelay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HlsPlaylistTest {
    private val masterUrl = "https://usher.ttvnw.net/api/channel/hls/somechannel.m3u8?token=abc"

    private val masterPlaylist = """
        #EXTM3U
        #EXT-X-TWITCH-INFO:NODE="video-edge",MANIFEST-NODE="video-weaver"
        #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60 (source)",AUTOSELECT=YES,DEFAULT=YES
        #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.64002A,mp4a.40.2",VIDEO="chunked",FRAME-RATE=60.000
        https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/source.m3u8
        #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="720p60",NAME="720p60",AUTOSELECT=YES,DEFAULT=NO
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="avc1.4D401F,mp4a.40.2",VIDEO="720p60",FRAME-RATE=60.000
        https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/720p60.m3u8
        #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="480p30",NAME="480p",AUTOSELECT=YES,DEFAULT=NO
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,CODECS="avc1.4D401F,mp4a.40.2",VIDEO="480p30",FRAME-RATE=30.000
        https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/480p30.m3u8
    """.trimIndent()

    private val mediaPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:2.000,live
        https://example.cloudfront.net/segment1.ts
        #EXTINF:2.000,live
        segment2.ts
        #EXT-X-TWITCH-PREFETCH:https://example.cloudfront.net/segment3.ts
    """.trimIndent()

    @Test
    fun `detects master playlists`() {
        assertTrue(HlsPlaylist.isMasterPlaylist(masterPlaylist))
        assertFalse(HlsPlaylist.isMasterPlaylist(mediaPlaylist))
    }

    @Test
    fun `parses master playlist variants with names from media tags`() {
        val variants = HlsPlaylist.parseMaster(masterPlaylist, masterUrl)

        assertEquals(3, variants.size)
        assertEquals("1080p60 (source)", variants[0].name)
        assertEquals("1920x1080", variants[0].resolution)
        assertEquals(6000000L, variants[0].bandwidth)
        assertEquals(60.0, variants[0].frameRate!!, 0.001)
        assertEquals(
            "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/source.m3u8",
            variants[0].url,
        )
        assertEquals("720p60", variants[1].name)
        assertEquals("480p", variants[2].name)
    }

    @Test
    fun `parses relative variant urls against the master url`() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
            variants/720p.m3u8
        """.trimIndent()

        val variants = HlsPlaylist.parseMaster(
            playlist,
            "https://usher.ttvnw.net/api/channel/hls/somechannel.m3u8",
        )

        assertEquals(
            "https://usher.ttvnw.net/api/channel/hls/variants/720p.m3u8",
            variants.single().url,
        )
        assertEquals("1280x720", variants.single().name)
    }

    @Test
    fun `rewrites master playlist variant urls`() {
        val rewritten = HlsPlaylist.rewriteMaster(masterPlaylist, masterUrl) { url ->
            "/media.m3u8?src=${RelayUrls.encodeSrc(url)}"
        }

        assertFalse(rewritten.contains("https://video-weaver"))
        val variantLines = rewritten.lines().filter { it.startsWith("/media.m3u8?src=") }
        assertEquals(3, variantLines.size)
        assertEquals(
            "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/source.m3u8",
            RelayUrls.decodeSrc(variantLines[0].substringAfter("src=")),
        )
        // Tags without URLs must be untouched.
        assertTrue(rewritten.contains("#EXT-X-TWITCH-INFO:NODE=\"video-edge\""))
    }

    @Test
    fun `rewrites media playlist segments, map uri, and prefetch hints`() {
        val mediaUrl = "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/source.m3u8"
        val rewritten = HlsPlaylist.rewriteMedia(mediaPlaylist, mediaUrl) { url ->
            "/segment?src=${RelayUrls.encodeSrc(url)}"
        }

        val lines = rewritten.lines()
        // Segment urls (absolute and relative) are rewritten.
        assertEquals(
            "https://example.cloudfront.net/segment1.ts",
            RelayUrls.decodeSrc(
                lines.first { it.startsWith("/segment?src=") }.substringAfter("src="),
            ),
        )
        assertEquals(
            "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/segment2.ts",
            RelayUrls.decodeSrc(
                lines.filter { it.startsWith("/segment?src=") }[1].substringAfter("src="),
            ),
        )
        // EXT-X-MAP URI is rewritten and resolved.
        val mapLine = lines.first { it.startsWith("#EXT-X-MAP:") }
        assertEquals(
            "https://video-weaver.sea01.hls.ttvnw.net/v1/playlist/init.mp4",
            RelayUrls.decodeSrc(mapLine.substringAfter("src=").substringBefore("\"")),
        )
        // Twitch prefetch hints are rewritten so the Cast device never hits upstream.
        val prefetchLine = lines.first { it.startsWith("#EXT-X-TWITCH-PREFETCH:") }
        assertEquals(
            "https://example.cloudfront.net/segment3.ts",
            RelayUrls.decodeSrc(prefetchLine.substringAfter("src=")),
        )
        // Duration tags are untouched.
        assertTrue(rewritten.contains("#EXTINF:2.000,live"))
    }

    @Test
    fun `selects variant by exact name`() {
        val variants = HlsPlaylist.parseMaster(masterPlaylist, masterUrl)

        assertEquals("720p60", HlsPlaylist.selectVariant(variants, "720p60")?.name)
        assertEquals("480p", HlsPlaylist.selectVariant(variants, "480P")?.name)
    }

    @Test
    fun `selects variant by name prefix`() {
        val variants = HlsPlaylist.parseMaster(masterPlaylist, masterUrl)

        assertEquals(
            "1080p60 (source)",
            HlsPlaylist.selectVariant(variants, "1080p60")?.name,
        )
    }

    @Test
    fun `falls back to highest bandwidth variant`() {
        val variants = HlsPlaylist.parseMaster(masterPlaylist, masterUrl)

        assertEquals("1080p60 (source)", HlsPlaylist.selectVariant(variants, null)?.name)
        assertEquals(
            "1080p60 (source)",
            HlsPlaylist.selectVariant(variants, "nonexistent")?.name,
        )
        assertNull(HlsPlaylist.selectVariant(emptyList(), "720p60"))
    }

    @Test
    fun `parses attribute lists with quoted commas`() {
        val attributes = HlsPlaylist.parseAttributes(
            "BANDWIDTH=6000000,CODECS=\"avc1.64002A,mp4a.40.2\",RESOLUTION=1920x1080",
        )

        assertEquals("6000000", attributes["BANDWIDTH"])
        assertEquals("avc1.64002A,mp4a.40.2", attributes["CODECS"])
        assertEquals("1920x1080", attributes["RESOLUTION"])
    }
}
