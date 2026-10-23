package rt.kj

import com.snapchat.djinni.DjinniCppException

// The class of --kotlin-error-type for runtime.djinni.
class KjException : Exception {
    val error: KjError?

    constructor(error: KjError) : super(error.mMessage) {
        this.error = error
    }

    constructor(cause: DjinniCppException) : super(cause.message, cause) {
        this.error = null
    }
}
