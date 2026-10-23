package com.dropbox.djinni.test

import android.os.BadParcelableException
import android.os.Parcel

// The stub Parcel returns null for a byte array, as a Parcel without one does.
fun main() {
    try {
        ExternKotlinMessageParceler.create(Parcel())
    } catch (e: BadParcelableException) {
        println("parceler: a Parcel without a byte array throws BadParcelableException")
        return
    }
    throw AssertionError("the Parceler accepted a Parcel without a byte array")
}
