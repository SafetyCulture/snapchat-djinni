package rt.kj

import com.dropbox.djinni.testextern.ExternKotlinMessage
import java.util.EnumSet
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

    val service = requireNotNull(KjService.create()) { "KjService.create() returned null" }
    check(service.add(2, 3) == 5, "add")

    val item = KjItem("a", 3, arrayListOf("x", "y"), null)
    check(service.echo(item) == item, "echo of a record")

    // Records with arrays are equal when the content is equal.
    val blob = KjBlob(byteArrayOf(1, 2, 3), intArrayOf(4, 5))
    val echoed = service.echoBlob(blob)
    check(echoed == blob && echoed.hashCode() == blob.hashCode(), "content equality of arrays")
    check(echoed != KjBlob(byteArrayOf(1, 2, 3), intArrayOf(4, 6)), "different arrays")

    // An extern type with Kotlin keys goes between its pure Kotlin class and C++ as bytes.
    val message = ExternKotlinMessage(byteArrayOf(9, 8, 7))
    check(service.echoMessage(message) == message, "echo of an extern message")
    val box = KjMessageBox(message, arrayListOf(message, ExternKotlinMessage(byteArrayOf())), null)
    check(service.echoMessageBox(box) == box, "echo of a record with extern messages")
    check(service.echoMessageBox(KjMessageBox(message, arrayListOf(), message)).mMaybe == message, "optional extern message")

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
        check(e.message?.contains("boom") == true, "exception message: ${e.message}")
    }

    // optional<enum> and optional<flags> round trips, null and set
    check(service.invertOpt(null) == null, "invertOpt(null) stays null")
    check(service.invertOpt(KjColor.RED) == KjColor.GREEN, "invertOpt(RED) is GREEN")
    check(service.flagsOpt(null) == null, "flagsOpt(null) stays null")
    check(service.flagsOpt(EnumSet.of(KjFlags.FLAG_A, KjFlags.FLAG_B)) == EnumSet.of(KjFlags.FLAG_A, KjFlags.FLAG_B), "flagsOpt keeps the set")

    // Many threads call one object.
    val pool = Executors.newFixedThreadPool(8)
    val sum = AtomicInteger()
    val tasks = (0 until 2000).map { i -> pool.submit { sum.addAndGet(service.add(i, 1)) } }
    tasks.forEach { it.get() }
    check(sum.get() == (0 until 2000).sumOf { it + 1 }, "concurrent calls")
    pool.shutdown()
    pool.awaitTermination(30, TimeUnit.SECONDS)

    // An enum goes through JNI by its ordinal.
    check(service.invert(KjColor.RED) == KjColor.GREEN, "enum")

    // A proxy of a C++ object that goes back to C++ and returns is the same Java object.
    check(service.echoService(service) === service, "proxy round trip")

    // C++ and Kotlin implement the same interface.
    check(service.callBoth(object : KjBoth() { override fun value(): Int = 5 }) == 5, "Kotlin implementation of +c +j")
    check(service.callBoth(service.makeBoth()) == 11, "C++ implementation of +c +j")

    // Proxies that are collected release their C++ objects.
    // Kept until the baseline count is read, so the JVM cannot collect them early
    val retained = MutableList(2000) { KjService.create() }
    var live = KjService.liveCount()
    check(live > 1000, "live services before GC: $live")
    retained.clear()
    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
    while (live > 10 && System.nanoTime() < deadline) {
        System.gc()
        Thread.sleep(100)
        live = KjService.liveCount()
    }
    check(live <= 10, "live services after GC: $live")
    check(service.add(1, 1) == 2, "service after GC")

    println("KOTLIN JNI RUNTIME OK")
    System.exit(0)
}
