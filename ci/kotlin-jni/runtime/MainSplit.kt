package rt.kj

import com.snapchat.djinni.Outcome

// The runtime test of --kotlin-jni-native-out (runtime_sync.djinni with --kotlin-error-type): the static methods are
// in NativeKjsService, and the proxies are KjsServiceCppProxy and KjsBothCppProxy.

private fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

private fun caught(block: () -> Unit): Throwable? =
    try {
        block()
        null
    } catch (e: Throwable) {
        e
    }

fun main(args: Array<String>) {
    System.load(args[0])

    // A static method returns a proxy, and a proxy method calls C++.
    val service = requireNotNull(NativeKjsService.create()) { "NativeKjsService.create() returned null" }
    check(service is KjsServiceCppProxy, "create() returns a KjsServiceCppProxy, not $service")
    check(service.add(2, 3) == 5, "add")

    // Static methods with the error type of the application.
    val quotient: Int = NativeKjsService.divideStatic(9, 3)
    check(quotient == 3, "static outcome value")
    val outcomeError = caught { NativeKjsService.divideStatic(1, 0) }
    check(outcomeError is KjsException && outcomeError.error?.mCode == 7, "divideStatic(1, 0) throws KjsException with code 7, not $outcomeError")
    val cppError = caught { NativeKjsService.failStatic() }
    check(cppError is KjsException && cppError.cause?.message == "static boom", "failStatic() throws KjsException, not $cppError")

    // The proxy of an interface with +c +j.
    val both = requireNotNull(service.makeBoth()) { "makeBoth() returned null" }
    check(both is KjsBothCppProxy, "makeBoth() returns a KjsBothCppProxy, not $both")
    val raw: Outcome<Int, KjsError> = both.divide(1, 0)
    check(raw.errorOrNull()?.mCode == 7, "the +c +j proxy returns the raw outcome")

    println("KOTLIN JNI SPLIT RUNTIME OK")
    System.exit(0)
}
