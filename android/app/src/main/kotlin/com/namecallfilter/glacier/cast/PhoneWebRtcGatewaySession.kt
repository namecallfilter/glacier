package com.namecallfilter.glacier.cast

import com.namecallfilter.glacier.streamproxy.CastRelayLanAddressSelector
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.DatagramSocket
import java.net.ServerSocket
import java.security.SecureRandom
import java.util.Collections
import java.util.Locale

class PhoneWebRtcGatewaySession private constructor(
    val channelPath: String,
    val title: String,
    val sourceUrl: String,
    val lanAddress: String,
    val port: Int,
    val icePort: Int,
    val bindAddress: String = BIND_ADDRESS,
    val gatewayHostedOnPhone: Boolean = true,
) {
    val whepUrl: String = "http://$lanAddress:$port/$channelPath/whep"
    val mediaMtxConfig: String = PhoneWebRtcGatewayMediaMtxConfig.build(this)

    companion object {
        const val BIND_ADDRESS = "0.0.0.0"
        const val DEFAULT_WEBRTC_PORT = 8889
        const val DEFAULT_WEBRTC_ICE_PORT = 8189

        fun create(
            channelLogin: String,
            title: String,
            sourceUrl: String,
            lanAddress: String,
            port: Int,
            icePort: Int = DEFAULT_WEBRTC_ICE_PORT,
            sessionToken: String = randomSessionToken(),
        ): PhoneWebRtcGatewaySession {
            val normalizedChannelLogin = normalizeChannelLogin(channelLogin)
            val normalizedSessionToken = normalizeSessionToken(sessionToken)
            require(normalizedChannelLogin.isNotEmpty()) {
                "Channel login is required for phone WebRTC gateway"
            }
            require(normalizedSessionToken.isNotEmpty()) {
                "Session token is required for phone WebRTC gateway"
            }
            require(sourceUrl.isNotBlank()) {
                "Source URL is required for phone WebRTC gateway"
            }
            require(port in 1..65535) {
                "WebRTC port must be between 1 and 65535"
            }
            require(icePort in 1..65535) {
                "WebRTC ICE port must be between 1 and 65535"
            }
            require(!isUnreachableAdvertisedAddress(lanAddress)) {
                "Phone WebRTC gateway must advertise a LAN IPv4 address"
            }

            return PhoneWebRtcGatewaySession(
                channelPath = "$normalizedChannelLogin-$normalizedSessionToken",
                title = title,
                sourceUrl = sourceUrl,
                lanAddress = lanAddress,
                port = port,
                icePort = icePort,
            )
        }

        fun fromChannelPath(
            channelPath: String,
            title: String,
            sourceUrl: String,
            lanAddress: String,
            port: Int,
            icePort: Int,
        ): PhoneWebRtcGatewaySession {
            val normalizedChannelPath = normalizeChannelPath(channelPath)
            require(normalizedChannelPath.isNotEmpty()) {
                "Channel path is required for phone WebRTC gateway"
            }
            require(sourceUrl.isNotBlank()) {
                "Source URL is required for phone WebRTC gateway"
            }
            require(port in 1..65535) {
                "WebRTC port must be between 1 and 65535"
            }
            require(icePort in 1..65535) {
                "WebRTC ICE port must be between 1 and 65535"
            }
            require(!isUnreachableAdvertisedAddress(lanAddress)) {
                "Phone WebRTC gateway must advertise a LAN IPv4 address"
            }

            return PhoneWebRtcGatewaySession(
                channelPath = normalizedChannelPath,
                title = title,
                sourceUrl = sourceUrl,
                lanAddress = lanAddress,
                port = port,
                icePort = icePort,
            )
        }

        fun normalizeChannelLogin(channelLogin: String): String {
            return channelLogin
                .trim()
                .lowercase(Locale.US)
                .replace(Regex("[^a-z0-9_]"), "_")
                .trim('_')
        }

        private fun normalizeChannelPath(channelPath: String): String {
            return channelPath
                .trim()
                .lowercase(Locale.US)
                .replace(Regex("[^a-z0-9_-]"), "_")
                .trim { character -> character == '_' || character == '-' }
        }

        private fun normalizeSessionToken(sessionToken: String): String {
            return sessionToken
                .trim()
                .lowercase(Locale.US)
                .replace(Regex("[^a-z0-9_]"), "_")
                .trim('_')
        }

        private fun randomSessionToken(): String {
            val bytes = ByteArray(8)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString(separator = "") { byte ->
                "%02x".format(byte)
            }
        }

        fun discoverLanIpv4Address(): String? {
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

            return CastRelayLanAddressSelector
                .select(candidates)
                ?.address
                ?.hostAddress
        }

        fun choosePort(preferredPort: Int = DEFAULT_WEBRTC_PORT): Int {
            if (isPortAvailable(preferredPort)) return preferredPort

            ServerSocket(0, 1, InetAddress.getByName(BIND_ADDRESS)).use { socket ->
                return socket.localPort
            }
        }

        fun chooseIcePort(
            preferredPort: Int = DEFAULT_WEBRTC_ICE_PORT,
            unavailablePorts: Set<Int> = emptySet(),
        ): Int {
            if (
                preferredPort !in unavailablePorts &&
                isPortAvailable(preferredPort) &&
                isUdpPortAvailable(preferredPort)
            ) {
                return preferredPort
            }

            repeat(25) {
                ServerSocket(0, 1, InetAddress.getByName(BIND_ADDRESS)).use { socket ->
                    val port = socket.localPort
                    if (port !in unavailablePorts && isUdpPortAvailable(port)) {
                        return port
                    }
                }
            }

            throw IllegalStateException("Unable to find an available WebRTC ICE port")
        }

        private fun isPortAvailable(port: Int): Boolean {
            return runCatching {
                ServerSocket(port, 1, InetAddress.getByName(BIND_ADDRESS)).use { }
            }.isSuccess
        }

        private fun isUdpPortAvailable(port: Int): Boolean {
            return runCatching {
                DatagramSocket(port, InetAddress.getByName(BIND_ADDRESS)).use { }
            }.isSuccess
        }

        private fun isUnreachableAdvertisedAddress(address: String): Boolean {
            val parsed = runCatching { InetAddress.getByName(address) }.getOrNull()
            return parsed !is Inet4Address ||
                parsed.isLoopbackAddress ||
                parsed.isAnyLocalAddress ||
                parsed.isLinkLocalAddress
        }
    }
}

object PhoneWebRtcGatewayMediaMtxConfig {
    fun build(session: PhoneWebRtcGatewaySession): String {
        return """
            logLevel: info

            api: false
            metrics: false
            pprof: false
            playback: false

            rtsp: false
            rtmp: false
            hls: false
            srt: false
            moq: false

            webrtc: true
            webrtcAddress: ${session.bindAddress}:${session.port}
            webrtcLocalUDPAddress: :${session.icePort}
            webrtcLocalTCPAddress: :${session.icePort}
            webrtcEncryption: false
            webrtcAllowOrigins: ["*"]
            webrtcIPsFromInterfaces: false
            webrtcAdditionalHosts: [${session.lanAddress}]

            paths:
              ${session.channelPath}:
                source: ${session.sourceUrl}
                sourceOnDemand: yes
                sourceOnDemandStartTimeout: 45s
                sourceOnDemandCloseAfter: 30s
        """.trimIndent()
    }
}
