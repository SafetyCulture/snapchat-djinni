package com.safetyculture.djinnisupport

import kotlinx.cinterop.BetaInteropApi
import kotlinx.cinterop.alloc
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import platform.Foundation.NSData
import platform.Foundation.NSError
import kotlinx.cinterop.ObjCObjectVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import platform.Foundation.dataWithBytesNoCopy

@OptIn(ExperimentalForeignApi::class, BetaInteropApi::class)
fun <ObjcProtoType> parseFromByteArray(
    bytes: ByteArray,
    parse: (NSData, CPointer<ObjCObjectVar<NSError?>>?) -> ObjcProtoType?
): ObjcProtoType = memScoped {
    bytes.usePinned { pinned ->
        val error: ObjCObjectVar<NSError?> = alloc<ObjCObjectVar<NSError?>>()
        val nsData = NSData.dataWithBytesNoCopy(
            bytes = pinned.addressOf(0),
            length = bytes.size.toULong(),
            freeWhenDone = false
        )

        val result = parse(nsData, error.ptr)
        if (result == null) {
            val errorMessage = error.value?.localizedDescription ?: "Unknown error"
            throw IllegalArgumentException("Failed to parse wire object: $errorMessage")
        }

        result
    }
}
