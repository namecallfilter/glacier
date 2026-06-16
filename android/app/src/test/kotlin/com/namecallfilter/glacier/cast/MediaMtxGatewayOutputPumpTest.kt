package com.namecallfilter.glacier.cast

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.InputStream
import java.io.InterruptedIOException

class MediaMtxGatewayOutputPumpTest {
    @Test
    fun treatsInterruptedProcessOutputAsNormalShutdown() {
        val rememberedLines = mutableListOf<String>()
        val logs = mutableListOf<String>()

        MediaMtxGatewayOutputPump.pump(
            inputStream = InterruptingAfterLineInputStream("MediaMTX stopped\n"),
            rememberOutput = { line -> rememberedLines.add(line) },
            log = { line -> logs.add(line) },
        )

        assertTrue(rememberedLines.contains("MediaMTX stopped"))
        assertTrue(logs.contains("phone_webrtc_gateway process=MediaMTX stopped"))
        assertTrue(
            logs.any { log ->
                log.contains("phone_webrtc_gateway action=log_stream_closed") &&
                    log.contains("InterruptedIOException")
            },
        )
    }
}

private class InterruptingAfterLineInputStream(
    line: String,
) : InputStream() {
    private val bytes = line.toByteArray()
    private var index = 0

    override fun read(): Int {
        if (index < bytes.size) {
            return bytes[index++].toInt() and 0xff
        }

        throw InterruptedIOException("read interrupted by close() on another thread")
    }
}
