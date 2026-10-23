package rt.kj

import com.snapchat.djinni.DjinniCppException
import com.snapchat.djinni.Outcome

// The runtime test of --kotlin-error-type without --kotlin-suspend-wrap (runtime_sync.djinni).

fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

// The exception of the block, or null when it returns.
fun caught(block: () -> Unit): Throwable? =
    try {
        block()
        null
    } catch (e: Throwable) {
        e
    }

// A C++ exception throws KjsException with the DjinniCppException as its cause.
fun checkCppException(e: Throwable?, message: String, what: String) {
    check(e is KjsException, "$what throws KjsException, not $e")
    if (e is KjsException) {
        check(e.error == null, "$what has no error value")
        val cause = e.cause
        check(cause is DjinniCppException && cause.message == message, "$what has the cause DjinniCppException($message), not $cause")
    }
}

// The error of an outcome throws KjsException with the error value.
fun checkOutcomeError(e: Throwable?, code: Int, what: String) {
    check(e is KjsException, "$what throws KjsException, not $e")
    if (e is KjsException) {
        check(e.error?.mCode == code, "$what has the error code $code, not ${e.error}")
        check(e.cause == null, "$what has no cause")
    }
}

fun main(args: Array<String>) {
    System.load(args[0])

    // Success: the functions return T.
    val service = requireNotNull(KjsService.create()) { "KjsService.create() returned null" }
    val sum: Int = service.add(2, 3)
    check(sum == 5, "add")
    service.ping()
    val quotient: Int = service.divide(10, 2)
    check(quotient == 5, "outcome value")

    // The error of an outcome.
    checkOutcomeError(caught { service.divide(1, 0) }, 7, "divide(1, 0)")

    // C++ exceptions.
    checkCppException(caught { service.fail() }, "boom", "fail()")
    checkCppException(caught { service.failVoid() }, "void boom", "failVoid()")
    checkCppException(caught { service.failUnknown() }, "unknown C++ exception", "failUnknown()")

    // Static methods.
    val staticQuotient: Int = KjsService.divideStatic(9, 3)
    check(staticQuotient == 3, "static outcome value")
    checkOutcomeError(caught { KjsService.divideStatic(1, 0) }, 7, "divideStatic(1, 0)")
    checkCppException(caught { KjsService.failStatic() }, "static boom", "failStatic()")

    // An interface that Kotlin can implement keeps the raw outcome.
    val both = requireNotNull(service.makeBoth()) { "makeBoth() returned null" }
    val raw: Outcome<Int, KjsError> = both.divide(1, 0)
    check(raw.errorOrNull()?.mCode == 7, "the +c +j proxy returns the raw outcome")
    val kotlinBoth = object : KjsBoth() {
        override fun divide(a: Int, b: Int): Outcome<Int, KjsError> = Outcome.fromError(KjsError("from Kotlin", 9))
    }
    checkOutcomeError(caught { service.callBoth(kotlinBoth, 1, 2) }, 9, "callBoth with a Kotlin error")

    // An exception of Kotlin code that goes through C++ stays as it is.
    val thrower = object : KjsListener() {
        override fun onValue(value: Int): Int = throw IllegalStateException("from Kotlin")
    }
    val fromKotlin = caught { service.callListener(thrower, 1) }
    check(fromKotlin is IllegalStateException && fromKotlin.message == "from Kotlin", "a Kotlin exception through C++ stays as it is, not $fromKotlin")
    val doubler = object : KjsListener() {
        override fun onValue(value: Int): Int = value * 2
    }
    check(service.callListener(doubler, 21) == 42, "call into Kotlin")

    println("KOTLIN JNI TYPED RUNTIME OK")
    System.exit(0)
}
