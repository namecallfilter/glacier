package com.namecallfilter.glacier.cast

import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import com.namecallfilter.glacier.streamproxy.StreamProxyMode
import org.junit.Assert.assertEquals
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

    @Test
    fun startupQualityUpdateDebouncesInsteadOfLoadingImmediately() {
        val action = contextUpdateLoadAction(
            sessionConnected = true,
            pendingLoad = true,
            previous = castStreamContext(quality = "highest"),
            next = castStreamContext(quality = "1080p60(Source)"),
        )

        assertEquals(CastContextUpdateLoadAction.DEBOUNCE_STARTUP, action)
    }

    @Test
    fun settledQualityUpdateLoadsImmediately() {
        val action = contextUpdateLoadAction(
            sessionConnected = true,
            pendingLoad = false,
            previous = castStreamContext(quality = "highest"),
            next = castStreamContext(quality = "1080p60(Source)"),
        )

        assertEquals(CastContextUpdateLoadAction.LOAD_NOW, action)
    }

    @Test
    fun existingConnectedSessionStartsReceiverStatusHandling() {
        val actions = existingCastSessionStartupActions(
            sessionConnected = true,
            pendingLoad = false,
        )

        assertTrue(actions.attachReceiverChannel)
        assertTrue(actions.startKeepAlive)
        assertTrue(actions.emitRoutes)
        assertFalse(actions.loadCurrent)
    }

    @Test
    fun disconnectedExistingSessionOnlyEmitsState() {
        val actions = existingCastSessionStartupActions(
            sessionConnected = false,
            pendingLoad = true,
        )

        assertFalse(actions.attachReceiverChannel)
        assertFalse(actions.startKeepAlive)
        assertFalse(actions.emitRoutes)
        assertFalse(actions.loadCurrent)
    }

    @Test
    fun pendingLoadRetriesWhenManifestIsNotAvailableYet() {
        val decision = pendingLoadRetryDecision(
            result = CastLoadAttemptResult.MISSING_MANIFEST,
            pendingLoad = true,
            sessionConnected = true,
            pendingLoadAgeMs = 1_000L,
        )

        assertTrue(decision.shouldRetry)
        assertEquals(500L, decision.delayMs)
    }

    @Test
    fun pendingLoadStopsRetryingAfterStartupWindowExpires() {
        val decision = pendingLoadRetryDecision(
            result = CastLoadAttemptResult.MISSING_MANIFEST,
            pendingLoad = true,
            sessionConnected = true,
            pendingLoadAgeMs = 30_001L,
        )

        assertFalse(decision.shouldRetry)
    }

    @Test
    fun receiverStatusWithoutTimelineOrPlaybackStateDoesNotConfirmLoad() {
        assertFalse(
            receiverStatusConfirmsLoad(
                CastReceiverStatus(
                    latencyMs = null,
                    seekableLatencyMs = null,
                    currentTimeSec = null,
                    rangeStartSec = null,
                    rangeEndSec = null,
                    liveEdgeTimeSec = null,
                    targetLatencySec = 2.25,
                    maxLatencySec = 5.0,
                    latencyReference = null,
                ),
            ),
        )
    }

    @Test
    fun receiverStatusBufferingOrPlayingConfirmsLoadEvenWithoutTimeline() {
        assertTrue(
            receiverStatusConfirmsLoad(
                CastReceiverStatus(
                    latencyMs = null,
                    seekableLatencyMs = null,
                    currentTimeSec = null,
                    rangeStartSec = null,
                    rangeEndSec = null,
                    liveEdgeTimeSec = null,
                    targetLatencySec = 2.25,
                    maxLatencySec = 5.0,
                    latencyReference = null,
                    playerState = "BUFFERING",
                ),
            ),
        )
        assertTrue(
            receiverStatusConfirmsLoad(
                CastReceiverStatus(
                    latencyMs = null,
                    seekableLatencyMs = null,
                    currentTimeSec = null,
                    rangeStartSec = null,
                    rangeEndSec = null,
                    liveEdgeTimeSec = null,
                    targetLatencySec = 2.25,
                    maxLatencySec = 5.0,
                    latencyReference = null,
                    playerState = "PLAYING",
                ),
            ),
        )
    }

    @Test
    fun receiverLoadDiagnosticConfirmsLoad() {
        assertTrue(
            receiverDiagnosticConfirmsLoad(
                CastReceiverDiagnostic(
                    action = "load",
                    fields = emptyMap(),
                ),
            ),
        )
        assertFalse(
            receiverDiagnosticConfirmsLoad(
                CastReceiverDiagnostic(
                    action = "buffering",
                    fields = emptyMap(),
                ),
            ),
        )
    }

    @Test
    fun receiverStatusWithSeekableRangeMeansMediaLoaded() {
        assertTrue(
            receiverHasMediaTimeline(
                CastReceiverStatus(
                    latencyMs = 2_300L,
                    seekableLatencyMs = 2_300L,
                    currentTimeSec = 24.5,
                    rangeStartSec = 0.0,
                    rangeEndSec = 26.8,
                    liveEdgeTimeSec = 26.8,
                    targetLatencySec = 2.25,
                    maxLatencySec = 2.9,
                    latencyReference = "absoluteLiveEdge",
                ),
            ),
        )
        assertFalse(
            receiverHasMediaTimeline(
                CastReceiverStatus(
                    latencyMs = null,
                    seekableLatencyMs = null,
                    currentTimeSec = null,
                    rangeStartSec = null,
                    rangeEndSec = null,
                    liveEdgeTimeSec = null,
                    targetLatencySec = 2.25,
                    maxLatencySec = 2.9,
                    latencyReference = null,
                ),
            ),
        )
    }

    @Test
    fun localWebViewIsSuspendedWhenCastStarts() {
        val change = localWebViewCastSuspensionChange(
            currentSuspendedWebViewIdentifier = null,
            targetWebViewIdentifier = 1L,
        )

        assertEquals(1L, change.suspendWebViewIdentifier)
        assertEquals(null, change.resumeWebViewIdentifier)
    }

    @Test
    fun localWebViewIsRestoredWhenCastStops() {
        val change = localWebViewCastSuspensionChange(
            currentSuspendedWebViewIdentifier = 1L,
            targetWebViewIdentifier = null,
        )

        assertEquals(null, change.suspendWebViewIdentifier)
        assertEquals(1L, change.resumeWebViewIdentifier)
    }

    @Test
    fun localWebViewSuspensionSwitchesWhenCastContextChanges() {
        val change = localWebViewCastSuspensionChange(
            currentSuspendedWebViewIdentifier = 1L,
            targetWebViewIdentifier = 2L,
        )

        assertEquals(2L, change.suspendWebViewIdentifier)
        assertEquals(1L, change.resumeWebViewIdentifier)
    }

    @Test
    fun localWebViewSuspensionDoesNothingWhenTargetIsAlreadySuspended() {
        val change = localWebViewCastSuspensionChange(
            currentSuspendedWebViewIdentifier = 1L,
            targetWebViewIdentifier = 1L,
        )

        assertEquals(null, change.suspendWebViewIdentifier)
        assertEquals(null, change.resumeWebViewIdentifier)
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
