package com.namecallfilter.glacier.castrelay

import com.namecallfilter.glacier.streamproxy.ProxyHttpRequest
import com.namecallfilter.glacier.streamproxy.ProxyHttpResponse
import com.namecallfilter.glacier.streamproxy.StreamProxyAction
import com.namecallfilter.glacier.streamproxy.StreamProxyConfig
import com.namecallfilter.glacier.streamproxy.StreamProxyFetcher
import com.namecallfilter.glacier.streamproxy.StreamProxyRequestRouter
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

/**
 * Local HTTP server that relays Twitch HLS playlists and segments to a Cast
 * device on the LAN. Playlist and segment requests are routed through the same
 * [StreamProxyRequestRouter]/[StreamProxyFetcher] core as WebView playback, so
 * the user's stream proxy settings apply to casting as well.
 *
 * Endpoints (upstream URL is base64url-encoded in the `src` query parameter):
 * - `/master.m3u8?src=` master playlist, variant URLs rewritten to `/media.m3u8`
 * - `/media.m3u8?src=` media playlist, segment URLs rewritten to `/segment`
 * - `/segment?src=` raw segment passthrough
 */
class CastRelayServer(
    private val log: (String) -> Unit,
) {
    @Volatile
    private var config: StreamProxyConfig = StreamProxyConfig.fromMap(null)

    private val router = StreamProxyRequestRouter()
    private val fetcher = StreamProxyFetcher(log)
    private val executor = Executors.newCachedThreadPool()

    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null

    val port: Int
        get() = serverSocket?.localPort ?: -1

    val isRunning: Boolean
        get() = serverSocket?.isClosed == false

    @Synchronized
    fun start(initialConfig: StreamProxyConfig): Int {
        config = initialConfig
        serverSocket?.let { socket ->
            if (!socket.isClosed) return socket.localPort
        }

        val socket = ServerSocket()
        socket.reuseAddress = true
        socket.bind(InetSocketAddress("0.0.0.0", 0))
        serverSocket = socket

        acceptThread = Thread({
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (_: IOException) {
                    break
                }
                executor.execute { handleConnection(client) }
            }
        }, "CastRelayAccept").also {
            it.isDaemon = true
            it.start()
        }

        log("relay action=started port=${socket.localPort}")
        return socket.localPort
    }

    @Synchronized
    fun stop() {
        val socket = serverSocket ?: return
        serverSocket = null
        runCatching { socket.close() }
        acceptThread = null
        log("relay action=stopped")
    }

    fun updateConfig(newConfig: StreamProxyConfig) {
        config = newConfig
    }

    /**
     * Fetches and parses the master playlist at [usherUrl], returning the
     * available variants with upstream URLs. Fetching through the proxy core
     * also teaches the router which video-weaver URLs belong to this channel.
     */
    fun resolveVariants(usherUrl: String): List<HlsVariant>? {
        val body = fetchPlaylistBody(usherUrl) ?: return null
        return HlsPlaylist.parseMaster(body, usherUrl)
    }

    private fun handleConnection(client: Socket) {
        try {
            client.soTimeout = SOCKET_TIMEOUT_MS
            val input = BufferedInputStream(client.getInputStream())
            val output = client.getOutputStream()

            val requestLine = readAsciiLine(input)
            if (requestLine.isNullOrEmpty()) return
            val parts = requestLine.split(" ")
            val method = parts.getOrNull(0)?.uppercase() ?: return
            val target = parts.getOrNull(1) ?: return
            // Drain request headers; the relay does not use them.
            while (true) {
                val line = readAsciiLine(input) ?: break
                if (line.isEmpty()) break
            }

            when (method) {
                "OPTIONS" -> writeResponse(output, 204, "No Content", null, ByteArray(0))
                "GET" -> handleGet(target, output)
                else -> writeResponse(
                    output,
                    405,
                    "Method Not Allowed",
                    "text/plain",
                    "method not allowed".toByteArray(),
                )
            }
        } catch (error: Exception) {
            log("relay action=connection_failed reason=${error.javaClass.simpleName}")
        } finally {
            runCatching { client.close() }
        }
    }

    private fun handleGet(target: String, output: OutputStream) {
        val (path, query) = RelayUrls.parseRequestTarget(target)
        val src = query["src"]?.let(RelayUrls::decodeSrc)
        if (src == null) {
            writeResponse(output, 400, "Bad Request", "text/plain", "missing src".toByteArray())
            return
        }

        when (path) {
            RelayUrls.MASTER_PATH, RelayUrls.MEDIA_PATH -> servePlaylist(src, output)
            RelayUrls.SEGMENT_PATH -> serveSegment(src, output)
            else -> writeResponse(output, 404, "Not Found", "text/plain", "not found".toByteArray())
        }
    }

    private fun servePlaylist(upstreamUrl: String, output: OutputStream) {
        val body = fetchPlaylistBody(upstreamUrl)
        if (body == null) {
            writeResponse(
                output,
                502,
                "Bad Gateway",
                "text/plain",
                "upstream playlist fetch failed".toByteArray(),
            )
            return
        }

        val rewritten = if (HlsPlaylist.isMasterPlaylist(body)) {
            HlsPlaylist.rewriteMaster(body, upstreamUrl, RelayUrls::mediaPath)
        } else {
            HlsPlaylist.rewriteMedia(body, upstreamUrl, RelayUrls::segmentPath)
        }

        writeResponse(
            output,
            200,
            "OK",
            "application/vnd.apple.mpegurl",
            rewritten.toByteArray(StandardCharsets.UTF_8),
        )
    }

    private fun serveSegment(upstreamUrl: String, output: OutputStream) {
        val response = fetchUpstream(upstreamUrl, isPlaylist = false)
        if (response == null) {
            writeResponse(
                output,
                502,
                "Bad Gateway",
                "text/plain",
                "upstream segment fetch failed".toByteArray(),
            )
            return
        }

        response.body.use { body ->
            writeResponseHeaders(
                output,
                response.statusCode,
                response.reasonPhrase,
                response.mimeType ?: "video/mp2t",
                contentLength = null,
            )
            body.copyTo(output)
            output.flush()
        }
    }

    private fun fetchPlaylistBody(url: String): String? {
        val response = fetchUpstream(url, isPlaylist = true) ?: return null
        if (response.statusCode !in 200..299) {
            log("relay action=playlist_failed status=${response.statusCode}")
            runCatching { response.body.close() }
            return null
        }
        return response.body.use { String(it.readBytes(), StandardCharsets.UTF_8) }
    }

    /**
     * Routes the upstream request through the shared proxy router. Playlist
     * requests carry the TTV-LOL-PRO accept flag the router uses to identify
     * eligible playback requests, matching the page script's behavior in
     * WebView playback.
     */
    private fun fetchUpstream(url: String, isPlaylist: Boolean): ProxyHttpResponse? {
        val headers = mutableMapOf("User-Agent" to USER_AGENT)
        if (isPlaylist) {
            headers["Accept"] = "application/x-mpegURL, TTV-LOL-PRO"
        }
        val request = ProxyHttpRequest(url = url, method = "GET", headers = headers)

        val currentConfig = config
        val decision = router.route(
            url = url,
            method = request.method,
            headers = request.headers,
            config = currentConfig,
        )

        return try {
            if (decision.action == StreamProxyAction.PROXY) {
                fetcher.fetch(request, decision, currentConfig, router)
                    ?: fetcher.fetchDirect(request, decision, router, "relay_proxy_failed")
            } else {
                fetcher.fetchDirect(
                    request,
                    decision,
                    router,
                    decision.reason ?: "relay_direct",
                )
            }
        } catch (error: Exception) {
            log("relay action=fetch_failed reason=${error.javaClass.simpleName}")
            null
        }
    }

    private fun writeResponse(
        output: OutputStream,
        statusCode: Int,
        reason: String,
        contentType: String?,
        body: ByteArray,
    ) {
        writeResponseHeaders(output, statusCode, reason, contentType, body.size.toLong())
        output.write(body)
        output.flush()
    }

    private fun writeResponseHeaders(
        output: OutputStream,
        statusCode: Int,
        reason: String,
        contentType: String?,
        contentLength: Long?,
    ) {
        val headers = buildString {
            append("HTTP/1.1 ")
            append(statusCode)
            append(" ")
            append(reason.ifEmpty { "OK" })
            append("\r\n")
            if (contentType != null) {
                append("Content-Type: ")
                append(contentType)
                append("\r\n")
            }
            if (contentLength != null) {
                append("Content-Length: ")
                append(contentLength)
                append("\r\n")
            }
            // The Cast media receiver requires CORS on every media response.
            append("Access-Control-Allow-Origin: *\r\n")
            append("Access-Control-Allow-Methods: GET, OPTIONS\r\n")
            append("Access-Control-Allow-Headers: *\r\n")
            append("Cache-Control: no-cache\r\n")
            append("Connection: close\r\n")
            append("\r\n")
        }
        output.write(headers.toByteArray(StandardCharsets.ISO_8859_1))
    }

    private fun readAsciiLine(input: BufferedInputStream): String? {
        val buffer = ByteArrayOutputStream()
        while (true) {
            val next = input.read()
            if (next == -1) {
                if (buffer.size() == 0) return null
                break
            }
            if (next == '\n'.code) break
            if (next != '\r'.code) {
                buffer.write(next)
            }
        }
        return buffer.toString(StandardCharsets.ISO_8859_1.name())
    }

    companion object {
        private const val SOCKET_TIMEOUT_MS = 20000
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/124.0.0.0 Mobile Safari/537.36"

        /** Returns the phone's site-local IPv4 address for use in Cast media URLs. */
        fun lanAddress(): String? {
            return runCatching {
                NetworkInterface.getNetworkInterfaces()
                    .asSequence()
                    .filter { it.isUp && !it.isLoopback }
                    .flatMap { it.inetAddresses.asSequence() }
                    .filterIsInstance<Inet4Address>()
                    .firstOrNull { it.isSiteLocalAddress }
                    ?.hostAddress
            }.getOrNull()
        }
    }
}
