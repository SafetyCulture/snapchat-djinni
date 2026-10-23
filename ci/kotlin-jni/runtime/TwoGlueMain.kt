package rt.two

import java.util.concurrent.TimeUnit

// Two glue sets of one C++ API in one library: each leg gets a proxy of its own class, one C++ object.

private fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

private class AListener : rt.two.a.TwoGlueListener() {
    override fun onValue(value: Int): Int = value + 1
}

private class BListener : rt.two.b.TwoGlueListener() {
    override fun onValue(value: Int): Int = value + 2
}

private fun exercise(a: rt.two.a.TwoGlueService?, b: rt.two.b.TwoGlueService?) {
    if (a == null || b == null) {
        check(false, "get() returned null")
        return
    }

    check(a.javaClass.name == "rt.two.a.TwoGlueService\$CppProxy", "A proxy class: ${a.javaClass.name}")
    check(b.javaClass.name == "rt.two.b.TwoGlueService\$CppProxy", "B proxy class: ${b.javaClass.name}")

    // One leg asked twice gets the same JVM object.
    check(rt.two.a.TwoGlueService.get() === a, "A cache")
    check(rt.two.b.TwoGlueService.get() === b, "B cache")
    check(a.self() === a, "A self")
    check(b.self() === b, "B self")

    check(a.value() == 41 && b.value() == 41, "value")

    // A Kotlin object of each leg goes through C++.
    check(a.callListener(AListener(), 1) == 2, "A listener")
    check(b.callListener(BListener(), 1) == 3, "B listener")

    val aRecord = rt.two.a.TwoGlueRecord(7, "seven")
    val echoedA = a.echo(aRecord)
    check(echoedA.value == 7 && echoedA.name == "seven", "A record")

    val bRecord = rt.two.b.TwoGlueRecord(8, "eight")
    val echoedB = b.echo(bRecord)
    check(echoedB.value == 8 && echoedB.name == "eight", "B record")

    check(a.invert(rt.two.a.TwoGlueColor.RED) == rt.two.a.TwoGlueColor.GREEN, "A enum")
    check(b.invert(rt.two.b.TwoGlueColor.BLUE) == rt.two.b.TwoGlueColor.RED, "B enum")

    check(rt.two.a.TwoGlueService.released() == 0, "released before the collector")
}

fun main(args: Array<String>) {
    System.load(args[0])

    var a: rt.two.a.TwoGlueService? = rt.two.a.TwoGlueService.get()
    var b: rt.two.b.TwoGlueService? = rt.two.b.TwoGlueService.get()
    exercise(a, b)
    a = null
    b = null

    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
    while (rt.two.a.TwoGlueService.released() < 1 && System.nanoTime() < deadline) {
        System.gc()
        Thread.sleep(100)
    }
    check(rt.two.a.TwoGlueService.released() == 1,
        "the C++ object is released once, not ${rt.two.a.TwoGlueService.released()}")

    println("TWO GLUE SETS OK")
    System.exit(0)
}
