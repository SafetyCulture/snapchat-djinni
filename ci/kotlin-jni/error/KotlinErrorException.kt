package com.dropbox.djinni.test

import com.snapchat.djinni.DjinniCppException

// The class of --kotlin-error-type for the test-suite cases kotlin_error and kotlin_error_async.
class KotlinErrorException : Exception {
    val error: KotlinErrorError?

    constructor(error: KotlinErrorError) : super(error.mMessage) {
        this.error = error
    }

    constructor(cause: DjinniCppException) : super(cause.message, cause) {
        this.error = null
    }
}
