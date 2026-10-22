package rt.kj

import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

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

    val service = KjService.create()
    check(service.add(2, 3) == 5, "add")

    val item = KjItem("a", 3, arrayListOf("x", "y"), null)
    check(service.echo(item) == item, "echo of a record")

    val ok = service.divide(10, 2)
    check(ok.resultOr(-1) == 5, "outcome value")
    val failed = service.divide(1, 0)
    check(failed.errorOrNull()?.mCode == 7, "outcome error")

    check(service.callListener(Doubler(), 21) == 42, "call into Kotlin")

    check(service.delayed(7, 50).get() == 7, "future")

    try {
        service.fail()
        check(false, "a C++ exception must throw")
    } catch (e: RuntimeException) {
        check(e.message!!.contains("boom"), "exception message: ${e.message}")
    }

    // Many threads call one object.
    val pool = Executors.newFixedThreadPool(8)
    val sum = AtomicInteger()
    val tasks = (0 until 2000).map { i -> pool.submit { sum.addAndGet(service.add(i, 1)) } }
    tasks.forEach { it.get() }
    check(sum.get() == (0 until 2000).sumOf { it + 1 }, "concurrent calls")
    pool.shutdown()
    pool.awaitTermination(30, TimeUnit.SECONDS)

    println("KOTLIN JNI RUNTIME OK")
    System.exit(0)
}
