package com.namecallfilter.glacier.cast

import android.content.Context
import android.os.Build
import java.io.File

data class PhoneWebRtcGatewayBinaryAvailability(
    val available: Boolean,
    val binaryPath: String = "",
    val supportedAbis: List<String> = emptyList(),
    val reason: String = "",
    val userMessage: String = "",
    val diagnosticMessage: String = "",
)

class PhoneWebRtcGatewayUnavailableException(
    val availability: PhoneWebRtcGatewayBinaryAvailability,
) : IllegalStateException(availability.userMessage)

object PhoneWebRtcGatewayBinary {
    const val LIBRARY_NAME = "libmediamtx.so"

    data class Resolved(
        val path: String,
    )

    fun resolve(nativeLibraryDir: String): Resolved {
        return Resolved(
            path = nativeLibraryDir.trimEnd('/', '\\') + "/$LIBRARY_NAME",
        )
    }

    fun availability(
        nativeLibraryDir: String,
        fileExists: (String) -> Boolean,
        canExecute: (String) -> Boolean,
        supportedAbis: List<String> = emptyList(),
    ): PhoneWebRtcGatewayBinaryAvailability {
        val binary = resolve(nativeLibraryDir)
        val diagnostic = "path=${binary.path} supported_abis=${supportedAbis.joinToString(",")}"

        if (!fileExists(binary.path)) {
            return PhoneWebRtcGatewayBinaryAvailability(
                available = false,
                binaryPath = binary.path,
                supportedAbis = supportedAbis,
                reason = MISSING_PACKAGED_MEDIAMTX_REASON,
                userMessage = MISSING_PACKAGED_MEDIAMTX_MESSAGE,
                diagnosticMessage = diagnostic,
            )
        }

        if (!canExecute(binary.path)) {
            return PhoneWebRtcGatewayBinaryAvailability(
                available = false,
                binaryPath = binary.path,
                supportedAbis = supportedAbis,
                reason = MEDIAMTX_NOT_EXECUTABLE_REASON,
                userMessage = MEDIAMTX_NOT_EXECUTABLE_MESSAGE,
                diagnosticMessage = diagnostic,
            )
        }

        return PhoneWebRtcGatewayBinaryAvailability(
            available = true,
            binaryPath = binary.path,
            supportedAbis = supportedAbis,
            diagnosticMessage = diagnostic,
        )
    }

    fun availability(context: Context): PhoneWebRtcGatewayBinaryAvailability {
        return availability(
            nativeLibraryDir = context.applicationInfo.nativeLibraryDir.orEmpty(),
            fileExists = { path -> File(path).isFile },
            canExecute = { path -> File(path).canExecute() },
            supportedAbis = Build.SUPPORTED_ABIS.toList(),
        )
    }

    fun requireAvailable(context: Context): Resolved {
        val availability = availability(context)
        if (!availability.available) {
            throw PhoneWebRtcGatewayUnavailableException(availability)
        }

        return Resolved(availability.binaryPath)
    }

    private const val MISSING_PACKAGED_MEDIAMTX_REASON = "missing_packaged_mediamtx"
    private const val MISSING_PACKAGED_MEDIAMTX_MESSAGE =
        "Low Latency casting needs the packaged MediaMTX gateway, but it is not included for this device."
    private const val MEDIAMTX_NOT_EXECUTABLE_REASON = "packaged_mediamtx_not_executable"
    private const val MEDIAMTX_NOT_EXECUTABLE_MESSAGE =
        "Low Latency casting needs the packaged MediaMTX gateway, but Android did not extract it as an executable file."
}
