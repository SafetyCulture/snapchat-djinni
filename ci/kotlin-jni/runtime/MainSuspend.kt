package rt.kj

import kotlinx.coroutines.CancellationException
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
import java.lang.ref.WeakReference
import kotlin.coroutines.coroutineContext

class Doubler : KjListener() {
    override fun onValue(value: Int): Int = value * 2
}

fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
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
        val service = requireNotNull(KjService.create()) { "KjService.create() returned null" }
        check(service.add(2, 3) == 5, "add")

        val item = KjItem("a", 3, arrayListOf("x"), null)
        check(service.echo(item) == item, "echo of a record")

        // An outcome is not unwrapped.
        check(service.divide(10, 2).resultOr(-1) == 5, "outcome value")
        check(service.divide(1, 0).errorOrNull()?.mCode == 7, "outcome error")

        // C++ calls a Kotlin object from the thread of the dispatcher.
        check(service.callListener(Doubler(), 21) == 42, "call into Kotlin")

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

        // A cancelled coroutine does not call C++.
        val early = launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            service.pending()
        }
        early.join()
        check(early.isCancelled, "an early cancelled coroutine is cancelled")

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

        // One C++ object runs one call at a time.
        coroutineScope {
            (0 until 40).map { async(Dispatchers.Default) { service.busy(5) } }.awaitAll()
        }
        check(service.maxConcurrent() == 1, "calls to one C++ object interleave: ${service.maxConcurrent()}")

        // Many coroutines use one object.
        val sum = coroutineScope {
            (0 until 1000).map { i -> async(Dispatchers.Default) { service.add(i, 1) } }.awaitAll().sum()
        }
        check(sum == (0 until 1000).sumOf { it + 1 }, "1000 coroutines: $sum")

        println("KOTLIN JNI SUSPEND RUNTIME OK")
    }
    System.exit(0)
}
