package com.safetyculture.crux.domain

import com.snapchat.djinni.DjinniCppException

// The class of --kotlin-error-type for the Crux pass of ci/kotlin-jni-check.sh. CruxError is the synthetic
// record crux_error that the pass adds to the Crux IDL.
class CruxException : Exception {
    val error: CruxError?

    constructor(error: CruxError) : super(error.mMessage) {
        this.error = error
    }

    constructor(cause: DjinniCppException) : super(cause.message, cause) {
        this.error = null
    }
}
