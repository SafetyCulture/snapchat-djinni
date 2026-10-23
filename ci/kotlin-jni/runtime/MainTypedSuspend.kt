package rt.kj

import com.snapchat.djinni.DjinniCppException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.coroutineContext

// The runtime test of --kotlin-error-type with --kotlin-suspend-wrap (runtime.djinni).

class Doubler : KjListener() {
    override fun onValue(value: Int): Int = value * 2
}

fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

// The exception of the block, or null when it returns. A CancellationException of the caller is an exception too.
suspend fun caught(block: suspend () -> Unit): Throwable? =
    try {
        block()
        null
    } catch (e: Throwable) {
        e
    }

// A C++ exception throws KjException with the DjinniCppException as its cause.
fun checkCppException(e: Throwable?, message: String, what: String) {
    check(e is KjException, "$what throws KjException, not $e")
    if (e is KjException) {
        check(e.error == null, "$what has no error value")
        val cause = e.cause
        check(cause is DjinniCppException && cause.message?.contains(message) == true, "$what has the cause DjinniCppException($message), not $cause")
    }
}

// The error of an outcome throws KjException with the error value.
fun checkOutcomeError(e: Throwable?, code: Int, what: String) {
    check(e is KjException, "$what throws KjException, not $e")
    if (e is KjException) {
        check(e.error?.mCode == code, "$what has the error code $code, not ${e.error}")
        check(e.cause == null, "$what has no cause")
    }
}

// Cancellation is a CancellationException, never KjException (KjException is not a CancellationException).
fun checkCancellation(e: Throwable?, what: String) {
    check(e is CancellationException && e.cause !is KjException, "$what throws CancellationException, not $e")
}

fun main(args: Array<String>) {
    System.load(args[0])
    // A watchdog fails the run when the runtime deadlocks.
    val watchdog = Thread {
        Thread.sleep(120_000)
        println("FAIL: watchdog timeout")
        Runtime.getRuntime().halt(3)
    }
    watchdog.isDaemon = true
    watchdog.start()

    runBlocking {
        // Success: the functions return T.
        val service = requireNotNull(KjService.create()) { "KjService.create() returned null" }
        val sum: Int = service.add(2, 3)
        check(sum == 5, "add")
        val quotient: Int = service.divide(10, 2)
        check(quotient == 5, "outcome value")
        val delayed: Int = service.delayed(7, 50)
        check(delayed == 7, "future value")
        val later: Int = service.divideLater(10, 2, 20)
        check(later == 5, "future of an outcome value")
        service.done()
        check(KjService.liveCount() >= 1, "static value")
        val staticQuotient: Int = KjService.divideStatic(9, 3)
        check(staticQuotient == 3, "static outcome value")
        val staticDelayed: Int = KjService.delayedStatic(3, 10)
        check(staticDelayed == 3, "static future value")

        // The error of an outcome, also in a future and in a static method.
        checkOutcomeError(caught { service.divide(1, 0) }, 7, "divide(1, 0)")
        checkOutcomeError(caught { service.divideLater(1, 0, 20) }, 7, "divideLater(1, 0)")
        checkOutcomeError(caught { KjService.divideStatic(1, 0) }, 7, "divideStatic(1, 0)")

        // C++ exceptions: a blocking call, a failed future, and a static method.
        checkCppException(caught { service.fail() }, "boom", "fail()")
        checkCppException(caught { service.failUnknown() }, "unknown C++ exception", "failUnknown()")
        checkCppException(caught { service.failingFuture() }, "failed future", "failingFuture()")
        checkCppException(caught { service.unknownFuture() }, "unknown C++ exception", "unknownFuture()")
        checkCppException(caught { KjService.failStatic() }, "static boom", "failStatic()")

        // A promise that C++ drops.
        checkCppException(caught { withTimeout(10_000) { service.dropped() } }, "broken promise", "dropped()")

        // Cancellation before the call: CancellationException, and C++ is not called.
        val startedBefore = service.pendingStarted()
        var early: Throwable? = null
        launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            early = caught { service.pending() }
        }.join()
        checkCancellation(early, "pending() in a cancelled coroutine")
        check(service.pendingStarted() == startedBefore, "a coroutine cancelled before the call does not call C++")
        var earlyStatic: Throwable? = null
        launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            earlyStatic = caught { KjService.delayedStatic(1, 10) }
        }.join()
        checkCancellation(earlyStatic, "delayedStatic() in a cancelled coroutine")

        // Cancellation while the call waits for the future.
        var waiting: Throwable? = null
        val waiter = launch(Dispatchers.Default) { waiting = caught { service.pending() } }
        delay(200)
        waiter.cancel()
        waiter.join()
        checkCancellation(waiting, "pending() cancelled while it waits")
        service.completePending(1)
        var waitingOutcome: Throwable? = null
        val outcomeWaiter = launch(Dispatchers.Default) { waitingOutcome = caught { service.divideLater(1, 0, 3000) } }
        delay(200)
        outcomeWaiter.cancel()
        outcomeWaiter.join()
        checkCancellation(waitingOutcome, "divideLater() cancelled while it waits")

        // A timeout is a cancellation too.
        val timeout = caught { withTimeout(100) { service.pending() } }
        check(timeout is TimeoutCancellationException, "a timeout throws TimeoutCancellationException, not $timeout")
        service.completePending(2)

        // An interface that Kotlin can implement keeps the raw form.
        check(service.callBoth(object : KjBoth() { override fun value(): Int = 5 }) == 5, "+c +j interface")
        check(requireNotNull(service.makeBoth()) { "makeBoth() returned null" }.value() == 11, "C++ implementation of +c +j")

        // An exception of Kotlin code that goes through C++ stays as it is.
        val thrower = object : KjListener() {
            override fun onValue(value: Int): Int = throw IllegalStateException("from Kotlin")
        }
        val fromKotlin = caught { service.callListener(thrower, 1) }
        check(fromKotlin is IllegalStateException && fromKotlin.message == "from Kotlin", "a Kotlin exception through C++ stays as it is, not $fromKotlin")
        check(service.callListener(Doubler(), 21) == 42, "call into Kotlin")

        println("KOTLIN JNI TYPED SUSPEND RUNTIME OK")
    }
    System.exit(0)
}
