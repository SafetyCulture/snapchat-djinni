package com.safetyculture.djinnisupport

import kotlinx.datetime.Instant
import platform.Foundation.NSDate
import platform.Foundation.timeIntervalSince1970

class TransformDate() {
    companion object {
        fun toObjc(instant: Instant): NSDate {
            return NSDate(instant.toEpochMilliseconds().toDouble())
        }

        fun fromObjc(date: NSDate): Instant {
            return Instant.fromEpochMilliseconds(date.timeIntervalSince1970.toLong())
        }
    }
}