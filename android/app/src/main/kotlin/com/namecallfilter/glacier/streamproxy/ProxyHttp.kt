package com.namecallfilter.glacier.streamproxy

import java.io.InputStream

/**
 * Transport-agnostic HTTP request/response models so the stream proxy core can
 * serve both WebView interception and the Cast relay server.
 */
data class ProxyHttpRequest(
    val url: String,
    val method: String,
    val headers: Map<String, String>,
)

class ProxyHttpResponse(
    val statusCode: Int,
    val reasonPhrase: String,
    val mimeType: String?,
    val encoding: String?,
    val headers: Map<String, String>,
    val body: InputStream,
)
