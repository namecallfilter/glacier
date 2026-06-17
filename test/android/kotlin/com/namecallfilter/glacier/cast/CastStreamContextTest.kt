package com.namecallfilter.glacier.cast

import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import com.namecallfilter.glacier.streamproxy.StreamProxyMode
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CastStreamContextTest {
    @Test
    fun receiverReloadIsRequiredWhenQualityChanges() {
        val previous = castStreamContext(quality = "1080p60")
        val next = castStreamContext(quality = "720p60")

        assertTrue(next.requiresReceiverReloadFrom(previous))
    }

    @Test
    fun receiverReloadIsNotRequiredForMetadataOnlyChanges() {
        val previous = castStreamContext(
            title = "Original title",
            subtitle = "Original subtitle",
            quality = "1080p60",
        )
        val next = castStreamContext(
            title = "Updated title",
            subtitle = "Updated subtitle",
            quality = "1080p60",
        )

        assertFalse(next.requiresReceiverReloadFrom(previous))
    }

    @Test
    fun receiverReloadIsRequiredWhenStreamIdentityChanges() {
        assertTrue(
            castStreamContext(channelLogin = "other")
                .requiresReceiverReloadFrom(castStreamContext(channelLogin = "streamer")),
        )
        assertTrue(
            castStreamContext(webViewIdentifier = 2)
                .requiresReceiverReloadFrom(castStreamContext(webViewIdentifier = 1)),
        )
    }

    @Test
    fun receiverReloadIsNotRequiredWithoutPreviousContext() {
        assertFalse(castStreamContext().requiresReceiverReloadFrom(null))
    }

    @Test
    fun connectedSessionLoadsCurrentMediaWhenQualityChanges() {
        val previous = castStreamContext(quality = "1080p60")
        val next = castStreamContext(quality = "720p60")

        assertTrue(
            shouldLoadCurrentForContextUpdate(
                sessionConnected = true,
                pendingLoad = false,
                previous = previous,
                next = next,
            ),
        )
    }

    @Test
    fun disconnectedSessionDoesNotLoadCurrentMediaForQualityChanges() {
        val previous = castStreamContext(quality = "1080p60")
        val next = castStreamContext(quality = "720p60")

        assertFalse(
            shouldLoadCurrentForContextUpdate(
                sessionConnected = false,
                pendingLoad = false,
                previous = previous,
                next = next,
            ),
        )
    }

    @Test
    fun connectedSessionLoadsCurrentMediaForPendingLoads() {
        assertTrue(
            shouldLoadCurrentForContextUpdate(
                sessionConnected = true,
                pendingLoad = true,
                previous = null,
                next = castStreamContext(),
            ),
        )
    }

    private fun castStreamContext(
        webViewIdentifier: Long = 1,
        channelLogin: String = "streamer",
        title: String = "Title",
        subtitle: String? = "Subtitle",
        quality: String? = "1080p60",
    ): CastStreamContext {
        return CastStreamContext(
            webViewIdentifier = webViewIdentifier,
            channelLogin = channelLogin,
            title = title,
            subtitle = subtitle,
            quality = quality,
            config = StreamProxyConfig(
                mode = StreamProxyMode.TTV_LOL_PRO,
                currentChannelLogin = channelLogin,
                proxyUrls = emptyList(),
                whitelistedChannels = emptySet(),
                debugLogging = false,
            ),
        )
    }
}
