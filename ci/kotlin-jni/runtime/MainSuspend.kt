package rt.kj

import com.snapchat.djinni.DjinniCppException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import kotlin.coroutines.coroutineContext

// The dispatcher of --kotlin-suspend-dispatcher in the second run of this program.
object TestDispatchers {
    val blocking: ExecutorCoroutineDispatcher = Executors.newCachedThreadPool { task ->
        Thread(task, "kj-blocking").apply { isDaemon = true }
    }.asCoroutineDispatcher()
}

class Doubler : KjListener() {
    @Volatile var thread: String = ""
    override fun onValue(value: Int): Int {
        thread = Thread.currentThread().name
        return value * 2
    }
}

fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

fun main(args: Array<String>) {
    System.load(args[0])
    // The thread name of the dispatcher that runs the C++ calls.
    val expectedThread = args.getOrElse(1) { "DefaultDispatcher-worker" }
    // A watchdog fails the run when the runtime deadlocks.
    val watchdog = Thread {
        Thread.sleep(120_000)
        println("FAIL: watchdog timeout")
        Runtime.getRuntime().halt(3)
    }
    watchdog.isDaemon = true
    watchdog.start()

    runBlocking {
        val service = requireNotNull(KjService.create()) { "KjService.create() returned null" }
        check(service.add(2, 3) == 5, "add")

        val item = KjItem("a", 3, arrayListOf("x"), null)
        check(service.echo(item) == item, "echo of a record")

        // An outcome is not unwrapped.
        check(service.divide(10, 2).resultOr(-1) == 5, "outcome value")
        check(service.divide(1, 0).errorOrNull()?.mCode == 7, "outcome error")

        // C++ calls a Kotlin object from the thread of the dispatcher.
        val doubler = Doubler()
        check(service.callListener(doubler, 21) == 42, "call into Kotlin")
        check(doubler.thread.startsWith(expectedThread), "the C++ call runs on $expectedThread, not ${doubler.thread}")

        // A future is a suspend function that returns the value.
        check(service.delayed(7, 50) == 7, "future")

        try {
            service.fail()
            check(false, "a C++ exception must throw")
        } catch (e: RuntimeException) {
            check(e.message?.contains("boom") == true, "exception message: ${e.message}")
        }

        check(service.invert(KjColor.RED) == KjColor.GREEN, "enum")
        check(service.echoService(service) === service, "proxy round trip")

        // An interface that Kotlin can implement is not a suspend interface.
        check(service.callBoth(object : KjBoth() { override fun value(): Int = 5 }) == 5, "+c +j interface")
        check(service.callBoth(requireNotNull(service.makeBoth()) { "makeBoth() returned null" }) == 11, "C++ implementation of +c +j")

        // A cancelled coroutine stops waiting. The C++ future is not cancelled.
        val waiting = launch(Dispatchers.Default) { service.pending() }
        delay(200)
        waiting.cancel()
        waiting.join()
        check(waiting.isCancelled, "a waiting coroutine is cancelled")
        service.completePending(1)
        delay(100)

        // A cancelled coroutine does not call C++: the counter of pending() calls must not move.
        val startedBefore = service.pendingStarted()
        val early = launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            service.pending()
        }
        early.join()
        check(early.isCancelled, "an early cancelled coroutine is cancelled")
        check(service.pendingStarted() == startedBefore, "a coroutine cancelled before the call does not call C++")

        // A cancelled coroutine is released before the C++ future completes.
        val published = CompletableDeferred<WeakReference<ByteArray>>()
        val big = launch(Dispatchers.Default) {
            val data = ByteArray(32 shl 20)
            published.complete(WeakReference(data))
            service.pending()
            check(data.isNotEmpty(), "the frame is live")
        }
        val frame = published.await()
        delay(200)
        big.cancel()
        big.join()
        var attempts = 0
        while (frame.get() != null && attempts++ < 100) {
            System.gc()
            delay(50)
        }
        check(frame.get() == null, "a cancelled coroutine stays in memory while the future waits")
        service.completePending(2)

        // A failed future throws the exception of C++. A future of void returns.
        try {
            service.failingFuture()
            check(false, "a failed future must throw")
        } catch (e: RuntimeException) {
            check(e.message == "failed future", "message of a failed future: ${e.message}")
        }
        service.done()

        // A C++ exception is a DjinniCppException. An exception outside std::exception does not stop the JVM.
        try {
            service.fail()
            check(false, "a C++ exception must throw")
        } catch (e: DjinniCppException) {
            check(e.message?.contains("boom") == true, "exception message: ${e.message}")
        }
        try {
            service.failUnknown()
            check(false, "an unknown C++ exception must throw")
        } catch (e: DjinniCppException) {
            check(e.message == "unknown C++ exception", "message of an unknown C++ exception: ${e.message}")
        }

        // A promise that C++ drops fails the call. A rejection with an exception outside std::exception fails it too.
        try {
            withTimeout(10_000) { service.dropped() }
            check(false, "a dropped promise must fail the call")
        } catch (e: DjinniCppException) {
            check(e.message?.contains("broken promise") == true, "dropped promise error: ${e.message}")
        } catch (e: CancellationException) {
            check(false, "the call on a dropped promise never returns")
        }
        try {
            withTimeout(10_000) { service.unknownFuture() }
            check(false, "an unknown rejection must fail the call")
        } catch (e: DjinniCppException) {
            check(e.message == "unknown C++ exception", "unknown rejection error: ${e.message}")
        } catch (e: CancellationException) {
            check(false, "the call on an unknown rejection never returns")
        }

        // A second call before complete_pending replaces the promise of the first call. The first call fails, and the
        // second call is not blocked. The count of C++ orders the calls: the second call starts when the first one has
        // stored its promise, also when the first call reaches C++ late.
        val replacedBefore = service.pendingStarted()
        val firstCall = async(Dispatchers.Default) { runCatching { service.pending() } }
        check(withTimeoutOrNull(10_000) { while (service.pendingStarted() == replacedBefore) delay(5) } != null, "the first call of pending() reaches C++")
        val secondCall = async(Dispatchers.Default) { service.pending() }
        val firstResult = withTimeoutOrNull(10_000) { firstCall.await() }
        check(firstResult?.exceptionOrNull() is DjinniCppException, "the first call fails when a second call replaces its promise: $firstResult")
        service.completePending(5)
        check(withTimeoutOrNull(10_000) { secondCall.await() } == 5, "the second call completes")

        // A late result is dropped.
        val late = launch(Dispatchers.Default) { service.delayed(3, 300) }
        delay(50)
        late.cancel()
        late.join()
        delay(500)
        check(service.delayed(9, 10) == 9, "calls after a late result")

        // A timeout is a cancellation too.
        try {
            withTimeout(100) { service.pending() }
            check(false, "the timeout must cancel")
        } catch (e: CancellationException) {
        }
        service.completePending(3)

        // Calls to one C++ object run at the same time.
        coroutineScope {
            (0 until 40).map { async(Dispatchers.Default) { service.busy(20) } }.awaitAll()
        }
        check(service.maxConcurrent() > 1, "calls to one C++ object run one at a time: ${service.maxConcurrent()}")

        // A call to an object does not wait for a blocking call on the same object, as cancel() must not.
        val blocking = launch(Dispatchers.Default) { service.busy(3000) }
        delay(200)
        val quick = withTimeoutOrNull(1500) { service.add(1, 1) }
        check(quick == 2, "a call waits for a blocking call on the same object")
        blocking.join()

        // Many coroutines use one object.
        val sum = coroutineScope {
            (0 until 1000).map { i -> async(Dispatchers.Default) { service.add(i, 1) } }.awaitAll().sum()
        }
        check(sum == (0 until 1000).sumOf { it + 1 }, "1000 coroutines: $sum")

        println("KOTLIN JNI SUSPEND RUNTIME OK")
    }
    System.exit(0)
}
