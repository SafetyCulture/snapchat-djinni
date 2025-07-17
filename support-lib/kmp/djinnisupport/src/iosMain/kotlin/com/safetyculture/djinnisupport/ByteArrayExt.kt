package com.safetyculture.djinnisupport

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.usePinned
import platform.Foundation.NSData
import platform.Foundation.dataWithBytes

@OptIn(ExperimentalForeignApi::class)
fun ByteArray.toNSData(): NSData = usePinned { pinned ->
    NSData.dataWithBytes(
        bytes = pinned.addressOf(0),
        length = this@toNSData.size.toULong()
    )
}

