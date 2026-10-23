package rt.kj

import com.snapchat.djinni.DjinniCppException

// The class of --kotlin-error-type for runtime_sync.djinni.
class KjsException : Exception {
    val error: KjsError?

    constructor(error: KjsError) : super(error.mMessage) {
        this.error = error
    }

    constructor(cause: DjinniCppException) : super(cause.message, cause) {
        this.error = null
    }
}
