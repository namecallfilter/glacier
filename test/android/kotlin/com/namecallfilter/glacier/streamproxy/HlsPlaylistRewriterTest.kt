package com.namecallfilter.glacier.streamproxy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HlsPlaylistRewriterTest {
    @Test
    fun parseMasterPlaylistBuildsQualityLabelsAndAbsoluteUrls() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=30.000,SCORE=0.7
            720/index.m3u8
        """.trimIndent()

        val master = HlsPlaylistRewriter.parseMasterPlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8?token=abc",
        )

        assertEquals(listOf("1080p60", "720p30"), master.variants.map { it.quality })
        assertEquals(
            "https://usher.ttvnw.net/api/channel/hls/source/index.m3u8",
            master.variants[0].url,
        )
        assertEquals(
            "https://usher.ttvnw.net/api/channel/hls/720/index.m3u8",
            master.variants[1].url,
        )
    }

    @Test
    fun rewritePlaylistFiltersMasterPlaylistToSelectedQuality() {
        val playlist = """
            #EXTM3U
            #EXT-X-VERSION:3
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=60.000,SCORE=0.7
            720/index.m3u8
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "720p60",
            rewriteUrl = { originalUrl ->
                "http://192.168.1.10:49200/relay/${originalUrl.substringAfterLast("/")}"
            },
        )

        assertEquals("720p60", result.selectedQuality)
        assertTrue(result.body.contains("#EXT-X-VERSION:3"))
        assertTrue(result.body.contains("RESOLUTION=1280x720"))
        assertTrue(result.body.contains("http://192.168.1.10:49200/relay/index.m3u8"))
        assertFalse(result.body.contains("RESOLUTION=1920x1080"))
        assertFalse(result.body.contains("source/index.m3u8"))
    }

    @Test
    fun rewritePlaylistMatchesTwitchQualityLabelsWithSuffixes() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=60.000,SCORE=0.7
            720/index.m3u8
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "1080p60 (Source)",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )

        assertEquals("1080p60", result.selectedQuality)
        assertTrue(result.body.contains("RESOLUTION=1920x1080"))
        assertFalse(result.body.contains("RESOLUTION=1280x720"))
    }

    @Test
    fun rewritePlaylistKeepsManualSourceQualityLockedToOneVariant() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=60.000,SCORE=0.7
            720/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480,FRAME-RATE=30.000,SCORE=0.4
            480/index.m3u8
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "1080p60(Source)",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )

        assertEquals("1080p60", result.selectedQuality)
        assertEquals(1, Regex("#EXT-X-STREAM-INF").findAll(result.body).count())
        assertTrue(result.body.contains("RESOLUTION=1920x1080"))
        assertFalse(result.body.contains("RESOLUTION=1280x720"))
        assertFalse(result.body.contains("RESOLUTION=854x480"))
    }

    @Test
    fun rewritePlaylistOnlyAutoExposesAllVariants() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=60.000,SCORE=0.7
            720/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480,FRAME-RATE=30.000,SCORE=0.4
            480/index.m3u8
        """.trimIndent()

        val autoResult = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "auto",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )
        val manualMissingResult = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "1080p60(Source)",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )

        assertEquals(2, Regex("#EXT-X-STREAM-INF").findAll(autoResult.body).count())
        assertEquals(0, Regex("#EXT-X-STREAM-INF").findAll(manualMissingResult.body).count())
    }

    @Test
    fun rewritePlaylistMatchesTwitchQualityLabelsWithoutFrameRate() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480,FRAME-RATE=30.000,SCORE=0.5
            480/index.m3u8
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "480p",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )

        assertEquals("480p30", result.selectedQuality)
        assertTrue(result.body.contains("RESOLUTION=854x480"))
        assertFalse(result.body.contains("RESOLUTION=1920x1080"))
    }

    @Test
    fun rewritePlaylistRewritesAllMediaPlaylistUrisThroughRelay() {
        val playlist = """
            #EXTM3U
            #EXT-X-MAP:URI="init.mp4"
            #EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin"
            #EXTINF:2.000,
            segment-1.ts
            #EXTINF:2.000,
            https://video-weaver.example.hls.ttvnw.net/v1/segment-2.ts
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8",
            selectedQuality = null,
            rewriteUrl = { originalUrl ->
                "http://phone/relay/${originalUrl.substringAfterLast("/")}"
            },
        )

        assertTrue(result.body.contains("#EXT-X-MAP:URI=\"http://phone/relay/init.mp4\""))
        assertTrue(result.body.contains("#EXT-X-KEY:METHOD=AES-128,URI=\"http://phone/relay/key.bin\""))
        assertTrue(result.body.contains("http://phone/relay/segment-1.ts"))
        assertTrue(result.body.contains("http://phone/relay/segment-2.ts"))
        assertEquals(
            listOf(
                "https://video-weaver.example.hls.ttvnw.net/v1/playlist/segment-1.ts",
                "https://video-weaver.example.hls.ttvnw.net/v1/segment-2.ts",
            ),
            result.prefetchUrls,
        )
        assertFalse(result.body.contains("\nsegment-1.ts"))
    }

    @Test
    fun rewritePlaylistRewritesLowLatencyHlsPartUrisThroughRelay() {
        val playlist = """
            #EXTM3U
            #EXT-X-PART-INF:PART-TARGET=0.33334
            #EXT-X-PART:DURATION=0.33334,URI="parts/segment-1.part0.m4s"
            #EXT-X-PART:DURATION=0.33334,URI="https://video-weaver.example.hls.ttvnw.net/v1/parts/segment-1.part1.m4s"
            #EXT-X-PRELOAD-HINT:TYPE=PART,URI="parts/segment-2.part0.m4s"
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8",
            selectedQuality = null,
            rewriteUrl = { originalUrl ->
                "http://phone/relay/${originalUrl.substringAfterLast("/")}"
            },
        )

        assertTrue(result.body.contains("#EXT-X-PART:DURATION=0.33334,URI=\"http://phone/relay/segment-1.part0.m4s\""))
        assertTrue(result.body.contains("#EXT-X-PART:DURATION=0.33334,URI=\"http://phone/relay/segment-1.part1.m4s\""))
        assertTrue(result.body.contains("#EXT-X-PRELOAD-HINT:TYPE=PART,URI=\"http://phone/relay/segment-2.part0.m4s\""))
        assertFalse(result.body.contains("URI=\"parts/segment-1.part0.m4s\""))
        assertFalse(result.body.contains("URI=\"parts/segment-2.part0.m4s\""))
    }

    @Test
    fun rewritePlaylistTrimsMediaPlaylistWindowAndCorrectsSequences() {
        val playlist = buildString {
            appendLine("#EXTM3U")
            appendLine("#EXT-X-VERSION:7")
            appendLine("#EXT-X-TARGETDURATION:2")
            appendLine("#EXT-X-MEDIA-SEQUENCE:100")
            appendLine("#EXT-X-DISCONTINUITY-SEQUENCE:3")
            appendLine("#EXT-X-KEY:METHOD=AES-128,URI=\"keys/live.key\"")
            appendLine("#EXT-X-MAP:URI=\"init/live.mp4\"")
            for (sequence in 100 until 120) {
                if (sequence == 104 || sequence == 112) {
                    appendLine("#EXT-X-DISCONTINUITY")
                }
                appendLine("#EXTINF:2.000,")
                appendLine("segment-$sequence.ts")
            }
        }.trimEnd()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8",
            selectedQuality = null,
            rewriteUrl = { originalUrl ->
                "http://phone/relay/${originalUrl.substringAfterLast("/")}"
            },
        )

        assertTrue(result.body.contains("#EXT-X-MEDIA-SEQUENCE:105"))
        assertTrue(result.body.contains("#EXT-X-DISCONTINUITY-SEQUENCE:4"))
        assertEquals(15, Regex("""segment-\d+\.ts""").findAll(result.body).count())
        assertFalse(result.body.contains("segment-104.ts"))
        assertTrue(result.body.contains("segment-105.ts"))
        assertTrue(result.body.contains("segment-119.ts"))
        assertTrue(result.body.contains("#EXT-X-DISCONTINUITY"))
    }

    @Test
    fun rewritePlaylistPreservesActiveKeyAndMapForFirstRetainedSegment() {
        val playlist = buildString {
            appendLine("#EXTM3U")
            appendLine("#EXT-X-VERSION:7")
            appendLine("#EXT-X-TARGETDURATION:2")
            appendLine("#EXT-X-MEDIA-SEQUENCE:200")
            appendLine("#EXT-X-KEY:METHOD=AES-128,URI=\"keys/live.key\"")
            appendLine("#EXT-X-MAP:URI=\"init/live.mp4\"")
            for (sequence in 200 until 220) {
                appendLine("#EXTINF:2.000,")
                appendLine("segment-$sequence.ts")
            }
        }.trimEnd()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://video-weaver.example.hls.ttvnw.net/v1/playlist/live.m3u8",
            selectedQuality = null,
            rewriteUrl = { originalUrl ->
                "http://phone/relay/${originalUrl.substringAfterLast("/")}"
            },
        )

        val firstSegmentIndex = result.body.indexOf("http://phone/relay/segment-205.ts")
        val keyIndex = result.body.indexOf(
            "#EXT-X-KEY:METHOD=AES-128,URI=\"http://phone/relay/live.key\"",
        )
        val mapIndex = result.body.indexOf(
            "#EXT-X-MAP:URI=\"http://phone/relay/live.mp4\"",
        )

        assertTrue(firstSegmentIndex >= 0)
        assertTrue(keyIndex in 0 until firstSegmentIndex)
        assertTrue(mapIndex in 0 until firstSegmentIndex)
        assertFalse(result.body.contains("segment-204.ts"))
    }

    @Test
    fun rewritePlaylistSelectsHighestVariantWhenRequested() {
        val playlist = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x720,FRAME-RATE=60.000,SCORE=0.7
            720/index.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080,FRAME-RATE=60.000,SCORE=1.0
            source/index.m3u8
        """.trimIndent()

        val result = HlsPlaylistRewriter.rewritePlaylist(
            body = playlist,
            baseUrl = "https://usher.ttvnw.net/api/channel/hls/streamer.m3u8",
            selectedQuality = "highest",
            rewriteUrl = { "http://phone/relay/${it.substringAfterLast("/")}" },
        )

        assertEquals("1080p60", result.selectedQuality)
        assertTrue(result.body.contains("RESOLUTION=1920x1080"))
        assertFalse(result.body.contains("RESOLUTION=1280x720"))
    }
}
