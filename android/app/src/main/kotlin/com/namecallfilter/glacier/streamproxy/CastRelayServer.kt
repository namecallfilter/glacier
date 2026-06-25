package com.namecallfilter.glacier.streamproxy

import java.io.Closeable
import java.io.InputStream
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Collections
import java.util.LinkedHashMap
import java.util.Locale
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class CastRelayServer(
    private val log: (String) -> Unit,
    private val nowMs: () -> Long = { System.currentTimeMillis() },
    private val mediaTargetTtlMs: Long = DEFAULT_MEDIA_TARGET_TTL_MS,
    private val maxMediaTargets: Int = DEFAULT_MAX_MEDIA_TARGETS,
    private val maxPlaylistTargets: Int = DEFAULT_MAX_PLAYLIST_TARGETS,
    private val segmentCacheTtlMs: Long = DEFAULT_SEGMENT_CACHE_TTL_MS,
    private val maxSegmentCacheEntries: Int = DEFAULT_MAX_SEGMENT_CACHE_ENTRIES,
    private val maxSegmentCacheBytes: Long = DEFAULT_MAX_SEGMENT_CACHE_BYTES,
) : Closeable {
    private val targets = ConcurrentHashMap<String, RelayTarget>()
    private val fetcher = StreamProxyFetcher(log)
    private val segmentFetchExecutor = RestartableSegmentExecutor(SEGMENT_FETCH_THREADS)
    private val segmentCache = SegmentMemoryCache(
        nowMs = nowMs,
        ttlMs = segmentCacheTtlMs,
        maxEntries = maxSegmentCacheEntries,
        maxBytes = maxSegmentCacheBytes,
        executor = segmentFetchExecutor,
    )

    @Volatile
    private var router = StreamProxyRequestRouter()

    @Volatile
    private var config = StreamProxyConfig(
        mode = StreamProxyMode.OFF,
        currentChannelLogin = "",
        proxyUrls = emptyList(),
        whitelistedChannels = emptySet(),
        debugLogging = false,
    )

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    private var baseUrl: String? = null

    fun update(
        router: StreamProxyRequestRouter,
        config: StreamProxyConfig,
    ) {
        this.router = router
        this.config = config
    }

    fun relayUrlFor(
        sourceUrl: String,
        selectedQuality: String? = null,
    ): String {
        ensureStarted()
        val relayBaseUrl = baseUrl ?: error("Cast relay did not start")
        val now = nowMs()
        evictTargets(now)
        val key = "$sourceUrl\n${selectedQuality.orEmpty()}"
        val id = stableTargetId(key)
        val existingTarget = targets[id]
        targets[id] = RelayTarget(
            sourceUrl = sourceUrl,
            selectedQuality = selectedQuality,
            kind = targetKindFor(sourceUrl),
            createdMs = existingTarget?.createdMs ?: now,
            lastAccessMs = now,
        )

        return "$relayBaseUrl/relay/$id.${extensionFor(sourceUrl)}"
    }

    override fun close() {
        serverSocket?.close()
        serverSocket = null
        baseUrl = null
        targets.clear()
        segmentCache.clear()
        segmentFetchExecutor.shutdownNow()
    }

    private fun ensureStarted() {
        if (serverSocket != null) return

        synchronized(this) {
            if (serverSocket != null) return

            val socket = ServerSocket(
                0,
                SERVER_BACKLOG,
                InetAddress.getByName("0.0.0.0"),
            )
            serverSocket = socket
            val relayAddress = lanAddress()
            baseUrl = "http://$relayAddress:${socket.localPort}"

            Thread {
                acceptLoop(socket)
            }.apply {
                isDaemon = true
                name = "GlacierCastRelay"
                start()
            }

            log("cast_relay action=started url=$baseUrl address=$relayAddress")
        }
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (!socket.isClosed) {
            try {
                val client = socket.accept()
                Thread {
                    handleClient(client)
                }.apply {
                    isDaemon = true
                    name = "GlacierCastRelayClient"
                    start()
                }
            } catch (error: Exception) {
                if (!socket.isClosed) {
                    log("cast_relay action=accept_failed reason=${error.javaClass.simpleName}")
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            val requestStartedNs = System.nanoTime()
            var requestForLog: HttpRequest? = null
            try {
                val request = readRequest(client)
                    ?: return
                requestForLog = request
                log(
                    "cast_relay action=request method=${request.method} " +
                        "path=${request.target.substringBefore("?")} " +
                        "from=${client.inetAddress.hostAddress}",
                )

                when (request.method.uppercase(Locale.US)) {
                    "OPTIONS" -> sendResponse(
                        socket = client,
                        statusCode = 204,
                        reasonPhrase = "No Content",
                        headers = corsHeaders(),
                        body = ByteArray(0),
                        headOnly = true,
                    )
                    "GET",
                    "HEAD" -> handleRelayRequest(client, request)
                    else -> sendError(client, 405, "Method Not Allowed")
                }
            } catch (error: Exception) {
                log(
                    relayRequestFailedLogLine(
                        method = requestForLog?.method,
                        path = requestForLog?.target?.substringBefore("?"),
                        totalMs = elapsedMs(requestStartedNs),
                        reason = error.javaClass.simpleName,
                        clientAborted = isLikelyClientAbort(error),
                    ),
                )
                runCatching { sendError(client, 500, "Internal Server Error") }
            }
        }
    }

    private fun handleRelayRequest(socket: Socket, request: HttpRequest) {
        val requestStartedNs = System.nanoTime()
        val path = request.target.substringBefore("?")
        if (!path.startsWith("/relay/")) {
            sendError(socket, 404, "Not Found")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=404 total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=9 playlist=false reason=invalid_path " +
                    "relay_targets=${targets.size}",
            )
            return
        }

        val id = path
            .removePrefix("/relay/")
            .substringBefore(".")
            .takeIf(String::isNotEmpty)
        val now = nowMs()
        evictTargets(now)
        if (id == null) {
            sendError(socket, 404, "Not Found")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=404 total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=9 playlist=false reason=missing_target " +
                    "relay_targets=${targets.size}",
            )
            return
        }
        val target = targets[id]
        if (target == null) {
            sendError(socket, 404, "Not Found")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=404 total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=9 playlist=false reason=missing_target " +
                    "relay_targets=${targets.size}",
            )
            return
        }
        if (target.isExpired(now, mediaTargetTtlMs)) {
            targets.remove(id, target)
            sendError(socket, 404, "Not Found")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=404 total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=9 playlist=false reason=expired_target " +
                    "relay_targets=${targets.size}",
            )
            return
        }
        targets[id] = target.copy(lastAccessMs = now)

        val currentConfig = config
        val currentRouter = router
        val upstreamUrl = upstreamUrlFor(
            sourceUrl = target.sourceUrl,
            relayTarget = request.target,
        )
        val playlistRequest = target.kind == RelayTargetKind.PLAYLIST
        val requestHeaders = CastRelayUpstreamHeaders.build(
            requestHeaders = request.headers,
            config = currentConfig,
            isPlaylistRequest = playlistRequest,
        )
        val upstreamMethod = if (request.method.equals("HEAD", ignoreCase = true)) {
            "HEAD"
        } else {
            "GET"
        }
        if (!playlistRequest) {
            handleMediaRelayRequest(
                socket = socket,
                request = request,
                path = path,
                upstreamUrl = upstreamUrl,
                requestHeaders = requestHeaders,
                currentConfig = currentConfig,
                currentRouter = currentRouter,
                requestStartedNs = requestStartedNs,
            )
            return
        }
        val upstreamRequest = StreamProxyRequest(
            url = upstreamUrl,
            method = upstreamMethod,
            headers = requestHeaders,
        )
        val decision = currentRouter.route(
            url = target.sourceUrl,
            method = upstreamMethod,
            headers = requestHeaders,
            config = currentConfig,
        )
        var effectiveUpstreamUrl = upstreamUrl
        val initialResponse = fetcher.fetch(
            request = upstreamRequest,
            decision = decision,
            config = currentConfig,
            router = currentRouter,
            directWhenSkipped = true,
        )
        val upstreamConnectedNs = System.nanoTime()

        if (initialResponse == null) {
            sendError(socket, 502, "Bad Gateway")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=502 " +
                    "source=${sourceDescription(upstreamUrl)} " +
                    "upstream_connect_ms=${elapsedMs(requestStartedNs, upstreamConnectedNs)} " +
                    "upstream_first_byte_ms=-1 " +
                    "total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=11 playlist=$playlistRequest reason=upstream_null " +
                    "relay_targets=${targets.size}",
            )
            return
        }

        var response = initialResponse
        if (playlistRequest && isStaleStatus(response.statusCode)) {
            val refreshedResponse = refreshStalePlaylist(
                originalUpstreamUrl = upstreamUrl,
                upstreamMethod = upstreamMethod,
                requestHeaders = requestHeaders,
                currentConfig = currentConfig,
                router = currentRouter,
                selectedQuality = target.selectedQuality,
                path = path,
            )
            if (refreshedResponse != null) {
                response.close()
                response = refreshedResponse.response
                effectiveUpstreamUrl = refreshedResponse.upstreamUrl
            }
        }

        response.use { upstream ->
            val headOnly = request.method.equals("HEAD", ignoreCase = true)
            val headers = responseHeaders(upstream)
            var mimeType = upstream.mimeType
            var selectedQuality: String? = null
            val playlistResponse = isPlaylistResponse(effectiveUpstreamUrl, upstream)
            var firstByteNs: Long? = null
            var playlistMetadata = PlaylistLiveEdgeMetadata()

            if (isStaleStatus(upstream.statusCode)) {
                val timedBody = if (headOnly) {
                    TimedBody(bytes = ByteArray(0), firstByteNs = null)
                } else {
                    readBodyWithTiming(upstream.body)
                }
                firstByteNs = timedBody.firstByteNs
                if (mimeType != null) {
                    headers["Content-Type"] = mimeType
                }
                headers.putAll(corsHeaders())
                headers["Content-Length"] = timedBody.bytes.size.toString()

                sendResponse(
                    socket = socket,
                    statusCode = upstream.statusCode,
                    reasonPhrase = upstream.reasonPhrase,
                    headers = headers,
                    body = timedBody.bytes,
                    headOnly = headOnly,
                )
                log(
                    "cast_relay action=response method=${request.method} " +
                        "path=$path status=${upstream.statusCode} " +
                        "source=${sourceDescription(effectiveUpstreamUrl)} " +
                        "upstream_connect_ms=${elapsedMs(requestStartedNs, upstreamConnectedNs)} " +
                        "upstream_first_byte_ms=${elapsedMsOrMissing(requestStartedNs, firstByteNs)} " +
                        "total_ms=${elapsedMs(requestStartedNs)} " +
                        "bytes=${timedBody.bytes.size} mime=${mimeType.orEmpty()} " +
                        "playlist=$playlistRequest selected_quality= " +
                        "reason=stale_upstream relay_targets=${targets.size}",
                )
                return@use
            }

            if (playlistResponse) {
                val body = if (headOnly) {
                    ByteArray(0)
                } else {
                    val timedBody = readBodyWithTiming(upstream.body)
                    firstByteNs = timedBody.firstByteNs
                    val playlist = decodeBody(timedBody.bytes, upstream.encoding)
                    val rewritten = HlsPlaylistRewriter.rewritePlaylist(
                        body = playlist,
                        baseUrl = effectiveUpstreamUrl,
                        selectedQuality = target.selectedQuality,
                        rewriteUrl = { nestedSourceUrl ->
                            relayUrlFor(nestedSourceUrl)
                        },
                    )
                    prefetchMediaTargets(
                        sourceUrls = rewritten.prefetchUrls,
                        currentConfig = currentConfig,
                        currentRouter = currentRouter,
                        requestHeaders = request.headers,
                    )
                    selectedQuality = rewritten.selectedQuality
                    val rewrittenMetadata = playlistLiveEdgeMetadata(rewritten.body)
                    playlistMetadata = rewrittenMetadata.copy(
                        mediaSequence = rewritten.mediaSequence?.toString()
                            ?: rewrittenMetadata.mediaSequence,
                        discontinuitySequence = rewritten.discontinuitySequence?.toString()
                            ?: rewrittenMetadata.discontinuitySequence,
                        segmentCount = rewritten.segmentCount
                            ?: rewrittenMetadata.segmentCount,
                    )
                    log(
                        "cast_relay action=playlist_edge " +
                            "path=$path media_sequence=${playlistMetadata.mediaSequence.orEmpty()} " +
                            "discontinuity_sequence=${playlistMetadata.discontinuitySequence.orEmpty()} " +
                            "segment_count=${playlistMetadata.segmentCount} " +
                            "program_date_time=${sanitizeLogValue(playlistMetadata.programDateTime)} " +
                            "target_duration=${playlistMetadata.targetDuration.orEmpty()} " +
                            "playlist_bytes=${timedBody.bytes.size} " +
                            "relay_targets=${targets.size}",
                    )
                    rewritten.body.toByteArray(StandardCharsets.UTF_8)
                }
                mimeType = "application/vnd.apple.mpegurl"
                headers["Content-Type"] = "$mimeType; charset=utf-8"
                CastRelayPlaylistHeaders.applyNoCache(headers)
                headers.putAll(corsHeaders())
                headers["Content-Length"] = body.size.toString()

                sendResponse(
                    socket = socket,
                    statusCode = upstream.statusCode,
                    reasonPhrase = upstream.reasonPhrase,
                    headers = headers,
                    body = body,
                    headOnly = headOnly,
                )
                log(
                    "cast_relay action=response method=${request.method} " +
                        "path=$path status=${upstream.statusCode} " +
                        "source=${sourceDescription(effectiveUpstreamUrl)} " +
                        "upstream_connect_ms=${elapsedMs(requestStartedNs, upstreamConnectedNs)} " +
                        "upstream_first_byte_ms=${elapsedMsOrMissing(requestStartedNs, firstByteNs)} " +
                        "total_ms=${elapsedMs(requestStartedNs)} " +
                        "bytes=${body.size} mime=${mimeType.orEmpty()} " +
                        "playlist=true selected_quality=${selectedQuality.orEmpty()} " +
                        "media_sequence=${playlistMetadata.mediaSequence.orEmpty()} " +
                        "discontinuity_sequence=${playlistMetadata.discontinuitySequence.orEmpty()} " +
                        "segment_count=${playlistMetadata.segmentCount} " +
                        "program_date_time=${sanitizeLogValue(playlistMetadata.programDateTime)} " +
                        "target_duration=${playlistMetadata.targetDuration.orEmpty()} " +
                        "relay_targets=${targets.size}",
                )
                return@use
            }

            if (mimeType != null && headers.keys.none {
                    it.equals("Content-Type", ignoreCase = true)
                }
            ) {
                headers["Content-Type"] = mimeType
            }
            upstreamHeader(upstream.headers, "Content-Length")
                ?.takeIf(String::isNotBlank)
                ?.let { contentLength ->
                    headers["Content-Length"] = contentLength
                }
            headers.putAll(corsHeaders())

            val streamResult = sendStreamingResponse(
                socket = socket,
                statusCode = upstream.statusCode,
                reasonPhrase = upstream.reasonPhrase,
                headers = headers,
                body = upstream.body,
                headOnly = headOnly,
            )
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=${upstream.statusCode} " +
                    "source=${sourceDescription(effectiveUpstreamUrl)} " +
                    "upstream_connect_ms=${elapsedMs(requestStartedNs, upstreamConnectedNs)} " +
                    "upstream_first_byte_ms=" +
                    "${elapsedMsOrMissing(requestStartedNs, streamResult.firstByteNs)} " +
                    "total_ms=${elapsedMs(requestStartedNs)} " +
                    "bytes=${streamResult.bytes} mime=${mimeType.orEmpty()} " +
                    "playlist=false selected_quality= relay_targets=${targets.size}",
            )
        }
    }

    private fun handleMediaRelayRequest(
        socket: Socket,
        request: HttpRequest,
        path: String,
        upstreamUrl: String,
        requestHeaders: Map<String, String>,
        currentConfig: StreamProxyConfig,
        currentRouter: StreamProxyRequestRouter,
        requestStartedNs: Long,
    ) {
        val acquire = segmentCache.getOrStart(
            key = upstreamUrl,
            prefetch = false,
        ) {
            fetchSegmentForCache(
                upstreamUrl = upstreamUrl,
                requestHeaders = requestHeaders,
                currentConfig = currentConfig,
                currentRouter = currentRouter,
            )
        }
        val waitStartedNs = System.nanoTime()
        val cachedResponse = try {
            acquire.future.get()
        } catch (error: Exception) {
            if (error is InterruptedException) {
                Thread.currentThread().interrupt()
            }
            sendError(socket, 502, "Bad Gateway")
            log(
                "cast_relay action=response method=${request.method} " +
                    "path=$path status=502 " +
                    "source=${sourceDescription(upstreamUrl)} " +
                    "upstream_connect_ms=-1 upstream_first_byte_ms=-1 " +
                    "upstream_read_complete_ms=-1 downstream_write_complete_ms=-1 " +
                    "total_ms=${elapsedMs(requestStartedNs)} bytes=11 mime=text/plain " +
                    "playlist=false selected_quality= relay_targets=${targets.size} " +
                    "cache_hit=${acquire.cacheHit} " +
                    "cache_wait_ms=${elapsedMs(waitStartedNs)} " +
                    "prefetch_lead_ms=${prefetchLeadMs(acquire, requestStartedNs)} " +
                    "upstream_mbps=0.00 downstream_mbps=0.00 route=direct " +
                    "reason=${error.javaClass.simpleName}",
            )
            return
        }
        val cacheWaitMs = if (acquire.cacheHit) {
            0L
        } else {
            elapsedMs(waitStartedNs)
        }
        val headOnly = request.method.equals("HEAD", ignoreCase = true)
        val downstreamStartedNs = System.nanoTime()
        sendResponse(
            socket = socket,
            statusCode = cachedResponse.statusCode,
            reasonPhrase = cachedResponse.reasonPhrase,
            headers = cachedResponse.headers,
            body = cachedResponse.bytes,
            headOnly = headOnly,
        )
        val downstreamCompleteNs = System.nanoTime()

        log(
            "cast_relay action=response method=${request.method} " +
                "path=$path status=${cachedResponse.statusCode} " +
                "source=${sourceDescription(upstreamUrl)} " +
                "upstream_connect_ms=${elapsedMs(cachedResponse.fetchStartedNs, cachedResponse.upstreamConnectedNs)} " +
                "upstream_first_byte_ms=" +
                "${elapsedMsOrMissing(cachedResponse.fetchStartedNs, cachedResponse.upstreamFirstByteNs)} " +
                "upstream_read_complete_ms=" +
                "${elapsedMs(cachedResponse.fetchStartedNs, cachedResponse.upstreamReadCompleteNs)} " +
                "downstream_write_complete_ms=${elapsedMs(downstreamStartedNs, downstreamCompleteNs)} " +
                "total_ms=${elapsedMs(requestStartedNs, downstreamCompleteNs)} " +
                "bytes=${cachedResponse.bytes.size} mime=${cachedResponse.mimeType.orEmpty()} " +
                "playlist=false selected_quality= relay_targets=${targets.size} " +
                "cache_hit=${acquire.cacheHit} cache_wait_ms=$cacheWaitMs " +
                "prefetch_lead_ms=${prefetchLeadMs(acquire, requestStartedNs)} " +
                "upstream_mbps=" +
                "${mbps(cachedResponse.bytes.size, cachedResponse.upstreamFirstByteNs, cachedResponse.upstreamReadCompleteNs)} " +
                "downstream_mbps=${mbps(cachedResponse.bytes.size, downstreamStartedNs, downstreamCompleteNs)} " +
                "route=${cachedResponse.route}",
        )
    }

    private fun prefetchMediaTargets(
        sourceUrls: List<String>,
        currentConfig: StreamProxyConfig,
        currentRouter: StreamProxyRequestRouter,
        requestHeaders: Map<String, String>,
    ) {
        val limit = maxSegmentCacheEntries.coerceAtLeast(0)
        if (limit == 0 || sourceUrls.isEmpty()) return

        val mediaRequestHeaders = CastRelayUpstreamHeaders.build(
            requestHeaders = requestHeaders,
            config = currentConfig,
            isPlaylistRequest = false,
        )
        sourceUrls
            .distinct()
            .takeLast(limit)
            .forEach { sourceUrl ->
                try {
                    segmentCache.getOrStart(
                        key = sourceUrl,
                        prefetch = true,
                    ) {
                        fetchSegmentForCache(
                            upstreamUrl = sourceUrl,
                            requestHeaders = mediaRequestHeaders,
                            currentConfig = currentConfig,
                            currentRouter = currentRouter,
                        )
                    }
                } catch (error: RejectedExecutionException) {
                    log(
                        "cast_relay action=prefetch_rejected " +
                            "source=${sourceDescription(sourceUrl)} " +
                            "reason=${error.javaClass.simpleName}",
                    )
                }
            }
    }

    private fun fetchSegmentForCache(
        upstreamUrl: String,
        requestHeaders: Map<String, String>,
        currentConfig: StreamProxyConfig,
        currentRouter: StreamProxyRequestRouter,
    ): CachedSegmentResponse {
        val fetchStartedNs = System.nanoTime()
        val upstreamMethod = "GET"
        val decision = currentRouter.route(
            url = upstreamUrl,
            method = upstreamMethod,
            headers = requestHeaders,
            config = currentConfig,
        )
        val upstreamRequest = StreamProxyRequest(
            url = upstreamUrl,
            method = upstreamMethod,
            headers = requestHeaders,
        )
        val upstreamResponse = fetcher.fetch(
            request = upstreamRequest,
            decision = decision,
            config = currentConfig,
            router = currentRouter,
            directWhenSkipped = true,
        )
        val upstreamConnectedNs = System.nanoTime()

        if (upstreamResponse == null) {
            val body = "Bad Gateway".toByteArray(StandardCharsets.UTF_8)
            val headers = corsHeaders() + mapOf(
                "Content-Type" to "text/plain; charset=utf-8",
                "Content-Length" to body.size.toString(),
            )
            return CachedSegmentResponse(
                statusCode = 502,
                reasonPhrase = "Bad Gateway",
                headers = headers,
                bytes = body,
                mimeType = "text/plain",
                fetchStartedNs = fetchStartedNs,
                upstreamConnectedNs = upstreamConnectedNs,
                upstreamFirstByteNs = null,
                upstreamReadCompleteNs = upstreamConnectedNs,
                route = routeName(decision, currentConfig),
            )
        }

        upstreamResponse.use { upstream ->
            val headers = responseHeaders(upstream)
            val timedBody = readBodyWithTiming(upstream.body)
            val upstreamReadCompleteNs = System.nanoTime()
            val mimeType = upstream.mimeType
            if (
                mimeType != null &&
                headers.keys.none { it.equals("Content-Type", ignoreCase = true) }
            ) {
                headers["Content-Type"] = mimeType
            }
            headers.putAll(corsHeaders())
            headers["Content-Length"] = timedBody.bytes.size.toString()

            return CachedSegmentResponse(
                statusCode = upstream.statusCode,
                reasonPhrase = upstream.reasonPhrase,
                headers = headers,
                bytes = timedBody.bytes,
                mimeType = mimeType,
                fetchStartedNs = fetchStartedNs,
                upstreamConnectedNs = upstreamConnectedNs,
                upstreamFirstByteNs = timedBody.firstByteNs,
                upstreamReadCompleteNs = upstreamReadCompleteNs,
                route = routeName(decision, currentConfig),
            )
        }
    }

    private fun refreshStalePlaylist(
        originalUpstreamUrl: String,
        upstreamMethod: String,
        requestHeaders: Map<String, String>,
        currentConfig: StreamProxyConfig,
        router: StreamProxyRequestRouter,
        selectedQuality: String?,
        path: String,
    ): RefreshedResponse? {
        val latestManifestUrl = router.latestUsherManifestUrl(currentConfig.currentChannelLogin)
            ?.takeIf { latestUrl -> latestUrl != originalUpstreamUrl }
            ?: return null
        val decision = router.route(
            url = latestManifestUrl,
            method = upstreamMethod,
            headers = requestHeaders,
            config = currentConfig,
        )
        val refreshedResponse = fetcher.fetch(
            request = StreamProxyRequest(
                url = latestManifestUrl,
                method = upstreamMethod,
                headers = requestHeaders,
            ),
            decision = decision,
            config = currentConfig,
            router = router,
            directWhenSkipped = true,
        ) ?: return null

        if (isStaleStatus(refreshedResponse.statusCode)) {
            refreshedResponse.close()
            log(
                "cast_relay action=stale_manifest_refresh path=$path " +
                    "status=failed http_status=${refreshedResponse.statusCode} " +
                    "selected_quality=${selectedQuality.orEmpty()} " +
                    "source=${sourceDescription(latestManifestUrl)}",
            )
            return null
        }

        log(
            "cast_relay action=stale_manifest_refresh path=$path " +
                "status=ok http_status=${refreshedResponse.statusCode} " +
                "selected_quality=${selectedQuality.orEmpty()} " +
                "source=${sourceDescription(latestManifestUrl)}",
        )
        return RefreshedResponse(
            upstreamUrl = latestManifestUrl,
            response = refreshedResponse,
        )
    }

    private fun evictTargets(now: Long) {
        val ttlCutoff = now - mediaTargetTtlMs
        targets.entries.removeIf { entry ->
            val target = entry.value
            target.kind == RelayTargetKind.MEDIA &&
                mediaTargetTtlMs >= 0L &&
                target.lastAccessMs < ttlCutoff
        }

        evictTargetsByKind(RelayTargetKind.MEDIA, maxMediaTargets)
        evictTargetsByKind(RelayTargetKind.PLAYLIST, maxPlaylistTargets)
    }

    private fun evictTargetsByKind(kind: RelayTargetKind, maxTargets: Int) {
        val limit = maxTargets.coerceAtLeast(0)
        val matchingTargets = targets.entries
            .filter { entry -> entry.value.kind == kind }
            .sortedWith(
                compareBy<MutableMap.MutableEntry<String, RelayTarget>> {
                    it.value.lastAccessMs
                }.thenBy { it.key },
            )
        val removeCount = matchingTargets.size - limit
        if (removeCount <= 0) return

        matchingTargets.take(removeCount).forEach { entry ->
            targets.remove(entry.key, entry.value)
        }
    }

    private fun responseHeaders(response: StreamProxyResponse): MutableMap<String, String> {
        return response.headers
            .filterKeys { name ->
                !hopByHopHeaders.contains(name.lowercase(Locale.US))
            }
            .toMutableMap()
    }

    private fun readRequest(socket: Socket): HttpRequest? {
        val input = socket.getInputStream().buffered()
        val requestLine = readAsciiLine(input) ?: return null
        val parts = requestLine.split(" ", limit = 3)
        if (parts.size < 2) return null

        val headers = linkedMapOf<String, String>()
        while (true) {
            val line = readAsciiLine(input) ?: break
            if (line.isEmpty()) break

            val separatorIndex = line.indexOf(":")
            if (separatorIndex <= 0) continue

            headers[line.substring(0, separatorIndex).trim()] =
                line.substring(separatorIndex + 1).trim()
        }

        return HttpRequest(
            method = parts[0],
            target = parts[1],
            headers = headers,
        )
    }

    private fun sendError(
        socket: Socket,
        statusCode: Int,
        reasonPhrase: String,
    ) {
        sendResponse(
            socket = socket,
            statusCode = statusCode,
            reasonPhrase = reasonPhrase,
            headers = corsHeaders() + mapOf("Content-Type" to "text/plain; charset=utf-8"),
            body = reasonPhrase.toByteArray(StandardCharsets.UTF_8),
            headOnly = false,
        )
    }

    private fun sendResponse(
        socket: Socket,
        statusCode: Int,
        reasonPhrase: String,
        headers: Map<String, String>,
        body: ByteArray,
        headOnly: Boolean,
    ) {
        val output = sendResponseHeaders(socket, statusCode, reasonPhrase, headers)
        if (!headOnly) {
            output.write(body)
        }
        output.flush()
    }

    private fun sendStreamingResponse(
        socket: Socket,
        statusCode: Int,
        reasonPhrase: String,
        headers: Map<String, String>,
        body: InputStream,
        headOnly: Boolean,
    ): StreamResult {
        val output = sendResponseHeaders(socket, statusCode, reasonPhrase, headers)
        if (headOnly) {
            output.flush()
            return StreamResult(bytes = 0L, firstByteNs = null)
        }

        val buffer = ByteArray(STREAM_BUFFER_SIZE)
        var bytes = 0L
        var firstByteNs: Long? = null

        while (true) {
            val count = body.read(buffer)
            if (count == -1) break
            if (count == 0) continue
            if (firstByteNs == null) {
                firstByteNs = System.nanoTime()
            }
            output.write(buffer, 0, count)
            bytes += count
        }
        output.flush()
        return StreamResult(bytes = bytes, firstByteNs = firstByteNs)
    }

    private fun readBodyWithTiming(input: InputStream): TimedBody {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(STREAM_BUFFER_SIZE)
        var firstByteNs: Long? = null

        while (true) {
            val count = input.read(buffer)
            if (count == -1) break
            if (count == 0) continue
            if (firstByteNs == null) {
                firstByteNs = System.nanoTime()
            }
            output.write(buffer, 0, count)
        }

        return TimedBody(
            bytes = output.toByteArray(),
            firstByteNs = firstByteNs,
        )
    }

    private fun sendResponseHeaders(
        socket: Socket,
        statusCode: Int,
        reasonPhrase: String,
        headers: Map<String, String>,
    ): java.io.OutputStream {
        val output = socket.getOutputStream()
        val headerText = buildString {
            append("HTTP/1.1 ")
            append(statusCode)
            append(" ")
            append(reasonPhrase)
            append("\r\n")
            headers.forEach { (name, value) ->
                append(name)
                append(": ")
                append(value)
                append("\r\n")
            }
            append("Connection: close\r\n")
            append("\r\n")
        }

        output.write(headerText.toByteArray(StandardCharsets.ISO_8859_1))
        output.flush()
        return output
    }

    private fun corsHeaders(): Map<String, String> {
        return mapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers" to "*",
        )
    }

    private fun readAsciiLine(input: java.io.BufferedInputStream): String? {
        val buffer = StringBuilder()
        while (true) {
            val next = input.read()
            if (next == -1) {
                if (buffer.isEmpty()) return null
                break
            }
            if (next == '\n'.code) break
            if (next != '\r'.code) {
                buffer.append(next.toChar())
            }
        }
        return buffer.toString()
    }

    private fun isPlaylistResponse(
        sourceUrl: String,
        response: StreamProxyResponse,
    ): Boolean {
        val mimeType = response.mimeType.orEmpty()
        return mimeType.contains("mpegurl", ignoreCase = true) ||
            mimeType.contains("m3u8", ignoreCase = true) ||
            URI(sourceUrl).path?.endsWith(".m3u8", ignoreCase = true) == true
    }

    private fun isPlaylistUrl(sourceUrl: String): Boolean {
        return runCatching {
            URI(sourceUrl).path?.endsWith(".m3u8", ignoreCase = true) == true
        }.getOrDefault(false)
    }

    private fun targetKindFor(sourceUrl: String): RelayTargetKind {
        return if (isPlaylistUrl(sourceUrl)) {
            RelayTargetKind.PLAYLIST
        } else {
            RelayTargetKind.MEDIA
        }
    }

    private fun isStaleStatus(statusCode: Int): Boolean {
        return statusCode == 401 || statusCode == 403 || statusCode == 404
    }

    private fun upstreamUrlFor(sourceUrl: String, relayTarget: String): String {
        val relayQuery = relayTarget
            .substringAfter("?", missingDelimiterValue = "")
            .takeIf(String::isNotEmpty)
            ?: return sourceUrl

        val fragmentIndex = sourceUrl.indexOf("#")
        val sourceWithoutFragment = if (fragmentIndex >= 0) {
            sourceUrl.substring(0, fragmentIndex)
        } else {
            sourceUrl
        }
        val fragment = if (fragmentIndex >= 0) {
            sourceUrl.substring(fragmentIndex)
        } else {
            ""
        }
        val separator = when {
            sourceWithoutFragment.endsWith("?") ||
                sourceWithoutFragment.endsWith("&") -> ""
            sourceWithoutFragment.contains("?") -> "&"
            else -> "?"
        }

        return "$sourceWithoutFragment$separator$relayQuery$fragment"
    }

    private fun upstreamHeader(headers: Map<String, String>, name: String): String? {
        return headers.entries
            .firstOrNull { (key, _) -> key.equals(name, ignoreCase = true) }
            ?.value
    }

    private fun decodeBody(bytes: ByteArray, encoding: String?): String {
        return try {
            bytes.toString(Charset.forName(encoding ?: "UTF-8"))
        } catch (_: Exception) {
            bytes.toString(Charsets.UTF_8)
        }
    }

    private fun playlistLiveEdgeMetadata(playlist: String): PlaylistLiveEdgeMetadata {
        var mediaSequence: String? = null
        var discontinuitySequence: String? = null
        var programDateTime: String? = null
        var targetDuration: String? = null
        var segmentCount = 0

        playlist.lineSequence()
            .map(String::trim)
            .filter(String::isNotEmpty)
            .forEach { line ->
                when {
                    line.startsWith("#EXT-X-MEDIA-SEQUENCE:", ignoreCase = true) -> {
                        mediaSequence = line.substringAfter(":").trim()
                    }
                    line.startsWith("#EXT-X-DISCONTINUITY-SEQUENCE:", ignoreCase = true) -> {
                        discontinuitySequence = line.substringAfter(":").trim()
                    }
                    line.startsWith("#EXT-X-PROGRAM-DATE-TIME:", ignoreCase = true) -> {
                        programDateTime = line.substringAfter(":").trim()
                    }
                    line.startsWith("#EXT-X-TARGETDURATION:", ignoreCase = true) -> {
                        targetDuration = line.substringAfter(":").trim()
                    }
                    !line.startsWith("#") -> {
                        segmentCount += 1
                    }
                }
            }

        return PlaylistLiveEdgeMetadata(
            mediaSequence = mediaSequence,
            discontinuitySequence = discontinuitySequence,
            programDateTime = programDateTime,
            targetDuration = targetDuration,
            segmentCount = segmentCount,
        )
    }

    private fun elapsedMs(startNs: Long, endNs: Long = System.nanoTime()): Long {
        return (endNs - startNs).coerceAtLeast(0L) / 1_000_000L
    }

    private fun elapsedMsOrMissing(startNs: Long, endNs: Long?): Long {
        return endNs?.let { elapsedMs(startNs, it) } ?: -1L
    }

    private fun prefetchLeadMs(
        acquire: SegmentCacheAcquire,
        requestStartedNs: Long,
    ): Long {
        if (!acquire.startedByPrefetch) return 0L

        return elapsedMs(acquire.fetchStartedNs, requestStartedNs)
    }

    private fun mbps(
        bytes: Int,
        startNs: Long?,
        endNs: Long,
    ): String {
        val effectiveStartNs = startNs ?: return "0.00"
        val seconds = (endNs - effectiveStartNs).coerceAtLeast(1L) / 1_000_000_000.0
        val megabits = bytes * 8.0 / 1_000_000.0

        return String.format(Locale.US, "%.2f", megabits / seconds)
    }

    private fun routeName(
        decision: StreamProxyDecision,
        config: StreamProxyConfig,
    ): String {
        return if (
            decision.action == StreamProxyAction.PROXY &&
            config.proxyUrls.isNotEmpty()
        ) {
            "proxy"
        } else {
            "direct"
        }
    }

    private fun sanitizeLogValue(value: String?): String {
        return value
            ?.replace(Regex("\\s+"), "_")
            ?.take(MAX_LOG_VALUE_LENGTH)
            .orEmpty()
    }

    private fun stableTargetId(key: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(StandardCharsets.UTF_8))

        return digest
            .take(12)
            .joinToString("") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }
    }

    private fun extensionFor(sourceUrl: String): String {
        val path = runCatching { URI(sourceUrl).path.orEmpty() }
            .getOrDefault("")
            .lowercase(Locale.US)

        return when {
            path.endsWith(".m3u8") -> "m3u8"
            path.endsWith(".ts") -> "ts"
            path.endsWith(".mp4") -> "mp4"
            path.endsWith(".m4s") -> "m4s"
            path.endsWith(".aac") -> "aac"
            else -> "bin"
        }
    }

    private fun sourceDescription(sourceUrl: String): String {
        return runCatching {
            val uri = URI(sourceUrl)
            uri.host.orEmpty()
        }.getOrDefault("unknown")
    }

    private fun lanAddress(): String {
        val interfaces = runCatching {
            Collections.list(NetworkInterface.getNetworkInterfaces())
        }.getOrDefault(emptyList())

        val candidates = interfaces
            .filter { networkInterface -> networkInterface.isUp && !networkInterface.isLoopback }
            .flatMap { networkInterface ->
                Collections.list(networkInterface.inetAddresses)
                    .filterIsInstance<Inet4Address>()
                    .map { address ->
                        CastRelayLanAddressSelector.Candidate(
                            interfaceName = networkInterface.name.orEmpty(),
                            displayName = networkInterface.displayName.orEmpty(),
                            address = address,
                        )
                    }
            }
        val selected = CastRelayLanAddressSelector.select(candidates)

        return selected?.address?.hostAddress ?: "127.0.0.1"
    }

    private data class HttpRequest(
        val method: String,
        val target: String,
        val headers: Map<String, String>,
    )

    private data class RelayTarget(
        val sourceUrl: String,
        val selectedQuality: String?,
        val kind: RelayTargetKind,
        val createdMs: Long,
        val lastAccessMs: Long,
    ) {
        fun isExpired(nowMs: Long, mediaTargetTtlMs: Long): Boolean {
            return kind == RelayTargetKind.MEDIA &&
                mediaTargetTtlMs >= 0L &&
                lastAccessMs < nowMs - mediaTargetTtlMs
        }
    }

    private enum class RelayTargetKind {
        PLAYLIST,
        MEDIA,
    }

    private data class RefreshedResponse(
        val upstreamUrl: String,
        val response: StreamProxyResponse,
    )

    private data class TimedBody(
        val bytes: ByteArray,
        val firstByteNs: Long?,
    )

    private data class CachedSegmentResponse(
        val statusCode: Int,
        val reasonPhrase: String,
        val headers: Map<String, String>,
        val bytes: ByteArray,
        val mimeType: String?,
        val fetchStartedNs: Long,
        val upstreamConnectedNs: Long,
        val upstreamFirstByteNs: Long?,
        val upstreamReadCompleteNs: Long,
        val route: String,
    )

    private data class SegmentCacheAcquire(
        val future: CompletableFuture<CachedSegmentResponse>,
        val cacheHit: Boolean,
        val startedByPrefetch: Boolean,
        val fetchStartedNs: Long,
    )

    private class RestartableSegmentExecutor(
        private val threadCount: Int,
    ) {
        private val lock = Any()

        @Volatile
        private var executor: ExecutorService = newExecutor()

        fun execute(command: Runnable) {
            var lastError: RejectedExecutionException? = null

            repeat(2) {
                val activeExecutor = synchronized(lock) {
                    if (executor.isShutdown || executor.isTerminated) {
                        executor = newExecutor()
                    }
                    executor
                }

                try {
                    activeExecutor.execute(command)
                    return
                } catch (error: RejectedExecutionException) {
                    lastError = error
                    synchronized(lock) {
                        if (executor === activeExecutor) {
                            executor = newExecutor()
                        }
                    }
                }
            }

            throw lastError ?: RejectedExecutionException("Segment executor rejected task")
        }

        fun shutdownNow() {
            synchronized(lock) {
                executor.shutdownNow()
            }
        }

        private fun newExecutor(): ExecutorService {
            return Executors.newFixedThreadPool(threadCount) { runnable ->
                Thread(runnable).apply {
                    isDaemon = true
                    name = "GlacierCastSegmentFetch"
                }
            }
        }
    }

    private class SegmentMemoryCache(
        private val nowMs: () -> Long,
        private val ttlMs: Long,
        maxEntries: Int,
        maxBytes: Long,
        private val executor: RestartableSegmentExecutor,
    ) {
        private val lock = Any()
        private val maxEntries = maxEntries.coerceAtLeast(0)
        private val maxBytes = maxBytes.coerceAtLeast(0L)
        private val entries = LinkedHashMap<String, SegmentCacheEntry>(
            16,
            0.75f,
            true,
        )
        private var currentBytes = 0L

        fun getOrStart(
            key: String,
            prefetch: Boolean,
            fetch: () -> CachedSegmentResponse,
        ): SegmentCacheAcquire {
            var entryToStart: SegmentCacheEntry? = null
            val acquire = synchronized(lock) {
                evictLocked(nowMs())
                val existing = entries[key]
                if (existing != null) {
                    existing.lastAccessMs = nowMs()
                    return@synchronized SegmentCacheAcquire(
                        future = existing.future,
                        cacheHit = existing.completedAtMs != null,
                        startedByPrefetch = existing.startedByPrefetch,
                        fetchStartedNs = existing.fetchStartedNs,
                    )
                }

                val entry = SegmentCacheEntry(
                    future = CompletableFuture(),
                    createdMs = nowMs(),
                    lastAccessMs = nowMs(),
                    fetchStartedNs = System.nanoTime(),
                    startedByPrefetch = prefetch,
                )
                entries[key] = entry
                entryToStart = entry
                SegmentCacheAcquire(
                    future = entry.future,
                    cacheHit = false,
                    startedByPrefetch = prefetch,
                    fetchStartedNs = entry.fetchStartedNs,
                )
            }

            val newEntry = entryToStart
            if (newEntry != null) {
                try {
                    executor.execute {
                        try {
                            val response = fetch()
                            newEntry.future.complete(response)
                            completeFetch(key, newEntry, response)
                        } catch (error: Throwable) {
                            newEntry.future.completeExceptionally(error)
                            removeEntry(key, newEntry)
                        }
                    }
                } catch (error: RejectedExecutionException) {
                    newEntry.future.completeExceptionally(error)
                    removeEntry(key, newEntry)
                    throw error
                }
            }

            return acquire
        }

        fun clear() {
            synchronized(lock) {
                entries.clear()
                currentBytes = 0L
            }
        }

        private fun completeFetch(
            key: String,
            entry: SegmentCacheEntry,
            response: CachedSegmentResponse,
        ) {
            synchronized(lock) {
                if (entries[key] !== entry) return

                val responseBytes = response.bytes.size.toLong()
                if (
                    response.statusCode !in 200..299 ||
                    responseBytes > maxBytes ||
                    maxEntries == 0 ||
                    maxBytes == 0L
                ) {
                    entries.remove(key)
                    return
                }

                entry.completedAtMs = nowMs()
                entry.completedBytes = responseBytes
                currentBytes += responseBytes
                evictLocked(nowMs())
            }
        }

        private fun removeEntry(key: String, entry: SegmentCacheEntry) {
            synchronized(lock) {
                if (entries[key] === entry) {
                    entries.remove(key)
                    currentBytes = (currentBytes - entry.completedBytes).coerceAtLeast(0L)
                }
            }
        }

        private fun evictLocked(now: Long) {
            if (ttlMs >= 0L) {
                val ttlCutoff = now - ttlMs
                val iterator = entries.entries.iterator()
                while (iterator.hasNext()) {
                    val entry = iterator.next().value
                    if (entry.completedAtMs != null && entry.lastAccessMs < ttlCutoff) {
                        currentBytes = (currentBytes - entry.completedBytes).coerceAtLeast(0L)
                        iterator.remove()
                    }
                }
            }

            while (entries.size > maxEntries || currentBytes > maxBytes) {
                if (!removeOldestCompletedLocked()) break
            }
        }

        private fun removeOldestCompletedLocked(): Boolean {
            val iterator = entries.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next().value
                if (entry.completedAtMs == null) continue

                currentBytes = (currentBytes - entry.completedBytes).coerceAtLeast(0L)
                iterator.remove()
                return true
            }

            return false
        }
    }

    private class SegmentCacheEntry(
        val future: CompletableFuture<CachedSegmentResponse>,
        val createdMs: Long,
        var lastAccessMs: Long,
        val fetchStartedNs: Long,
        val startedByPrefetch: Boolean,
        var completedAtMs: Long? = null,
        var completedBytes: Long = 0L,
    )

    private data class StreamResult(
        val bytes: Long,
        val firstByteNs: Long?,
    )

    private data class PlaylistLiveEdgeMetadata(
        val mediaSequence: String? = null,
        val discontinuitySequence: String? = null,
        val programDateTime: String? = null,
        val targetDuration: String? = null,
        val segmentCount: Int = 0,
    )

    private companion object {
        private const val SERVER_BACKLOG = 32
        private const val STREAM_BUFFER_SIZE = 64 * 1024
        private const val MAX_LOG_VALUE_LENGTH = 240
        private const val DEFAULT_MEDIA_TARGET_TTL_MS = 2 * 60 * 1000L
        private const val DEFAULT_MAX_MEDIA_TARGETS = 512
        private const val DEFAULT_MAX_PLAYLIST_TARGETS = 96
        private const val DEFAULT_SEGMENT_CACHE_TTL_MS = 2 * 60 * 1000L
        private const val DEFAULT_MAX_SEGMENT_CACHE_ENTRIES = 6
        private const val DEFAULT_MAX_SEGMENT_CACHE_BYTES = 24L * 1024L * 1024L
        private const val SEGMENT_FETCH_THREADS = 3

        private val hopByHopHeaders = setOf(
            "connection",
            "content-length",
            "host",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        )
    }
}

internal fun relayRequestFailedLogLine(
    method: String?,
    path: String?,
    totalMs: Long,
    reason: String,
    clientAborted: Boolean,
): String {
    return "cast_relay action=request_failed " +
        "method=${sanitizeRelayFailureValue(method)} " +
        "path=${sanitizeRelayFailureValue(path)} " +
        "total_ms=$totalMs " +
        "reason=${sanitizeRelayFailureValue(reason)} " +
        "client_aborted=$clientAborted"
}

private fun isLikelyClientAbort(error: Exception): Boolean {
    val reason = error.javaClass.simpleName
    return error is java.net.SocketException ||
        reason.contains("ConnectionReset", ignoreCase = true) ||
        reason.contains("BrokenPipe", ignoreCase = true)
}

private fun sanitizeRelayFailureValue(value: String?): String {
    return value
        ?.replace(Regex("\\s+"), "_")
        ?.take(160)
        .orEmpty()
}

internal object CastRelayLanAddressSelector {
    data class Candidate(
        val interfaceName: String,
        val displayName: String,
        val address: Inet4Address,
    )

    fun select(candidates: List<Candidate>): Candidate? {
        return candidates
            .filter { candidate ->
                val address = candidate.address
                !address.isLoopbackAddress &&
                    !address.isLinkLocalAddress &&
                    !address.isAnyLocalAddress
            }
            .maxWithOrNull(
                compareBy<Candidate> { interfaceScore(it) }
                    .thenBy { addressScore(it.address) },
            )
    }

    private fun interfaceScore(candidate: Candidate): Int {
        val name = "${candidate.interfaceName} ${candidate.displayName}"
            .lowercase(Locale.US)

        return when {
            preferredInterfaceTokens.any { name.contains(it) } -> 3
            avoidedInterfaceTokens.any { name.contains(it) } -> 0
            else -> 1
        }
    }

    private fun addressScore(address: Inet4Address): Int {
        return when {
            address.isSiteLocalAddress -> 2
            else -> 0
        }
    }

    private val preferredInterfaceTokens = listOf(
        "wlan",
        "wifi",
        "wi-fi",
        "eth",
        "ap",
        "bridge",
        "br-",
    )

    private val avoidedInterfaceTokens = listOf(
        "rmnet",
        "cell",
        "mobile",
        "pdp",
        "ccmni",
        "wwan",
        "tun",
        "tap",
        "vpn",
        "clat",
    )
}
