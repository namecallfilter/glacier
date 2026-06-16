package com.namecallfilter.glacier.cast

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PhoneWebRtcGatewayBinaryTest {
    @Test
    fun resolvesPackagedNativeMediaMtxExecutableFromNativeLibraryDirectory() {
        val binary = PhoneWebRtcGatewayBinary.resolve(
            nativeLibraryDir = "/data/app/com.namecallfilter.glacier/lib/arm64",
        )

        assertEquals(
            "/data/app/com.namecallfilter.glacier/lib/arm64/libmediamtx.so",
            binary.path,
        )
    }

    @Test
    fun reportsMissingPackagedNativeMediaMtxBeforeStartingReceiverPlayback() {
        val availability = PhoneWebRtcGatewayBinary.availability(
            nativeLibraryDir = "/data/app/com.namecallfilter.glacier/lib/arm64",
            fileExists = { false },
            canExecute = { false },
        )

        assertFalse(availability.available)
        assertEquals("missing_packaged_mediamtx", availability.reason)
        assertTrue(
            availability.userMessage.contains(
                "Low Latency casting needs the packaged MediaMTX gateway",
            ),
        )
        assertTrue(availability.diagnosticMessage.contains("libmediamtx.so"))
    }

    @Test
    fun reportsAvailableWhenPackagedNativeMediaMtxExistsAndCanExecute() {
        val availability = PhoneWebRtcGatewayBinary.availability(
            nativeLibraryDir = "/data/app/com.namecallfilter.glacier/lib/arm64",
            fileExists = { path -> path.endsWith("/libmediamtx.so") },
            canExecute = { path -> path.endsWith("/libmediamtx.so") },
        )

        assertTrue(availability.available)
        assertEquals("", availability.reason)
        assertEquals("", availability.userMessage)
    }

    @Test
    fun bundlesArm64AndroidMediaMtxExecutable() {
        val binary = File("src/main/jniLibs/arm64-v8a/libmediamtx.so")

        assertTrue("Missing bundled arm64 MediaMTX executable", binary.isFile)
        assertTrue("Bundled MediaMTX executable is empty", binary.length() > 1024 * 1024)

        val header = binary.inputStream().use { input ->
            input.readNBytes(20)
        }
        assertEquals(0x7f, header[0].toInt() and 0xff)
        assertEquals('E'.code, header[1].toInt())
        assertEquals('L'.code, header[2].toInt())
        assertEquals('F'.code, header[3].toInt())
        assertEquals("Expected a 64-bit ELF binary", 2, header[4].toInt())

        val machine = ByteBuffer
            .wrap(header, 18, 2)
            .order(ByteOrder.LITTLE_ENDIAN)
            .short
            .toInt() and 0xffff
        assertEquals("Expected an AArch64 ELF binary", 183, machine)
    }
}
