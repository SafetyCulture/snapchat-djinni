// Round trips every supported field kind between the Java classes of one generator run and the Kotlin JNI
// classes of another run, and checks the wrappers of the interfaces that Kotlin and Java implement.

import com.dropbox.djinni.bridgejava.KotlinJavaBridgeBoth as JavaBoth
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeColor as JavaColor
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeContainers as JavaContainers
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeError as JavaError
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeEverything as JavaEverything
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeFlags as JavaFlags
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeLeaf as JavaLeaf
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeListener as JavaListener
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeBoth as KotlinBoth
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeColor as KotlinColor
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeContainers as KotlinContainers
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeError as KotlinError
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeEverything as KotlinEverything
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeFlags as KotlinFlags
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeLeaf as KotlinLeaf
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeListener as KotlinListener
import com.dropbox.djinni.bridgekt.javabridge.toJava
import com.dropbox.djinni.bridgekt.javabridge.toKotlinJni
import com.dropbox.djinni.testextern.ExternJavaMessage
import com.dropbox.djinni.testextern.ExternKotlinMessage
import com.snapchat.djinni.Future
import com.snapchat.djinni.Outcome
import com.snapchat.djinni.Promise
import java.util.ArrayList
import java.util.Date
import java.util.EnumSet
import java.util.HashMap
import java.util.HashSet
import java.lang.ref.WeakReference
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

private fun check(condition: Boolean, message: String) {
    if (!condition) {
        println("FAIL: $message")
        System.exit(1)
    }
}

private fun <T> ready(value: T): Future<T> {
    val promise = Promise<T>()
    promise.setValue(value)
    return promise.getFuture()
}

private fun <T> failed(message: String): Future<T> {
    val promise = Promise<T>()
    promise.setException(IllegalStateException(message))
    return promise.getFuture()
}

private fun failureMessage(error: Throwable): String? {
    var current: Throwable? = error
    while (current != null) {
        if (current.message == "failed future") return current.message
        current = current.cause
    }
    return null
}

private fun kotlinEverything(): KotlinEverything = KotlinEverything(
    true, 8, 16, 32, 64, 1.5f, 2.5, "text", byteArrayOf(1, 2, 3), Date(1_700_000_000_000L),
    5, "maybe", KotlinLeaf(9, "maybe-leaf"),
    ArrayList(listOf(KotlinLeaf(10, "ten"), KotlinLeaf(11, "eleven"))),
    ArrayList(listOf("name")),
    HashSet(listOf("key", "other")),
    HashMap(mapOf("table" to KotlinLeaf(12, "twelve"))),
    HashMap(mapOf("nested" to ArrayList(listOf(KotlinLeaf(13, "thirteen"))))),
    HashSet(listOf(KotlinLeaf(15, "fifteen"), KotlinLeaf(16, "sixteen"))),
    HashSet(listOf(KotlinColor.RED, KotlinColor.BLUE)),
    arrayOf(KotlinLeaf(17, "seventeen"), KotlinLeaf(18, "eighteen")),
    HashMap(mapOf(KotlinColor.GREEN to KotlinLeaf(19, "nineteen"))),
    KotlinColor.GREEN, KotlinColor.BLUE,
    EnumSet.of(KotlinFlags.FIRST, KotlinFlags.THIRD), EnumSet.of(KotlinFlags.SECOND),
    KotlinLeaf(14, "fourteen"), "other text", 77, ExternKotlinMessage(byteArrayOf(9, 8)))

private fun javaEverything(): JavaEverything = JavaEverything(
    true, 8, 16, 32, 64, 1.5f, 2.5, "text", byteArrayOf(1, 2, 3), Date(1_700_000_000_000L),
    5, "maybe", JavaLeaf(9, "maybe-leaf"),
    ArrayList(listOf(JavaLeaf(10, "ten"), JavaLeaf(11, "eleven"))),
    ArrayList(listOf("name")),
    HashSet(listOf("key", "other")),
    HashMap(mapOf("table" to JavaLeaf(12, "twelve"))),
    HashMap(mapOf("nested" to ArrayList(listOf(JavaLeaf(13, "thirteen"))))),
    HashSet(listOf(JavaLeaf(15, "fifteen"), JavaLeaf(16, "sixteen"))),
    HashSet(listOf(JavaColor.RED, JavaColor.BLUE)),
    arrayOf(JavaLeaf(17, "seventeen"), JavaLeaf(18, "eighteen")),
    HashMap(mapOf(JavaColor.GREEN to JavaLeaf(19, "nineteen"))),
    JavaColor.GREEN, JavaColor.BLUE,
    EnumSet.of(JavaFlags.FIRST, JavaFlags.THIRD), EnumSet.of(JavaFlags.SECOND),
    JavaLeaf(14, "fourteen"), "other text", 77, ExternJavaMessage(byteArrayOf(9, 8)))

private class KotlinListenerImpl : KotlinListener() {
    override fun value(value: Int): Int = value + 1

    override fun optional(leaf: KotlinLeaf?): String? = leaf?.mName

    override fun list(items: ArrayList<KotlinLeaf>): ArrayList<String> = ArrayList(items.map { it.mName })

    override fun futureValue(value: Int): Future<Int> = ready(value + 1)

    override fun futureLeaf(leaf: KotlinLeaf): Future<KotlinLeaf> = ready(leaf)

    override fun futureOutcome(value: Int): Future<Outcome<KotlinLeaf, KotlinError>> =
        ready(if (value > 0) Outcome.fromResult(KotlinLeaf(20, "twenty")) else Outcome.fromError(KotlinError("failed", 9)))

    override fun failedLeafFuture(): Future<KotlinLeaf> = failed("failed future")

    override fun outcomeValue(value: Int): Outcome<KotlinLeaf, KotlinError> =
        if (value > 0) Outcome.fromResult(KotlinLeaf(21, "twenty-one")) else Outcome.fromError(KotlinError("failed", 9))

    override fun chain(other: KotlinListener?, value: Int): Int = (other?.value(value) ?: 0) + 1

    override fun self(): KotlinListener? = this

    override fun listeners(items: ArrayList<KotlinListener>): ArrayList<KotlinListener> = items

    override fun maybeListener(value: KotlinListener?): KotlinListener? = value

    override fun takeFuture(value: Future<KotlinLeaf>): Future<String> = ready(value.get().mName)

    override fun takeOutcome(value: Outcome<KotlinLeaf, KotlinError>): String = value.resultOr(null)?.mName ?: "error"
}

private class JavaListenerImpl : JavaListener() {
    override fun value(value: Int): Int = value + 2

    override fun optional(leaf: JavaLeaf?): String? = leaf?.name

    override fun list(items: ArrayList<JavaLeaf>): ArrayList<String> = ArrayList(items.map { it.name })

    override fun futureValue(value: Int): Future<Int> = ready(value + 2)

    override fun futureLeaf(leaf: JavaLeaf): Future<JavaLeaf> = ready(leaf)

    override fun futureOutcome(value: Int): Future<Outcome<JavaLeaf, JavaError>> =
        ready(if (value > 0) Outcome.fromResult(JavaLeaf(22, "twenty-two")) else Outcome.fromError(JavaError("failed", 9)))

    override fun failedLeafFuture(): Future<JavaLeaf> = failed("failed future")

    override fun outcomeValue(value: Int): Outcome<JavaLeaf, JavaError> =
        if (value > 0) Outcome.fromResult(JavaLeaf(23, "twenty-three")) else Outcome.fromError(JavaError("failed", 9))

    override fun chain(other: JavaListener?, value: Int): Int = (other?.value(value) ?: 0) + 2

    override fun self(): JavaListener? = this

    override fun listeners(items: ArrayList<JavaListener>): ArrayList<JavaListener> = items

    override fun maybeListener(value: JavaListener?): JavaListener? = value

    override fun takeFuture(value: Future<JavaLeaf>): Future<String> = ready(value.get().name)

    override fun takeOutcome(value: Outcome<JavaLeaf, JavaError>): String = value.resultOr(null)?.name ?: "error"
}

// The wrapper cache holds the source only weakly.
private fun weakListenerAfterConversion(): WeakReference<KotlinListener> {
    val listener = KotlinListenerImpl()
    val weak = WeakReference<KotlinListener>(listener)
    listener.toJava()
    return weak
}

private class KotlinBothImpl : KotlinBoth() {
    override fun ping(leaf: KotlinLeaf): KotlinLeaf = leaf
}

private class JavaBothImpl : JavaBoth() {
    override fun ping(leaf: JavaLeaf): JavaLeaf = leaf
}

// The Java equals of a flags field compares the EnumSet objects, so this program compares the fields.
private fun sameJava(a: JavaEverything, b: JavaEverything): Boolean =
    a.b == b.b &&
        a.eight == b.eight &&
        a.sixteen == b.sixteen &&
        a.thirtytwo == b.thirtytwo &&
        a.sixtyfour == b.sixtyfour &&
        a.fthirtytwo == b.fthirtytwo &&
        a.fsixtyfour == b.fsixtyfour &&
        a.text == b.text &&
        a.data.contentEquals(b.data) &&
        a.`when` == b.`when` &&
        a.maybe == b.maybe &&
        a.maybeText == b.maybeText &&
        a.maybeLeaf?.name == b.maybeLeaf?.name &&
        a.items.map { it.name } == b.items.map { it.name } &&
        a.names == b.names &&
        a.keys == b.keys &&
        a.table.mapValues { it.value.name } == b.table.mapValues { it.value.name } &&
        a.nested.mapValues { entry -> entry.value.map { it.name } } == b.nested.mapValues { entry -> entry.value.map { it.name } } &&
        a.leafSet.map { it.name }.toSet() == b.leafSet.map { it.name }.toSet() &&
        a.colorSet == b.colorSet &&
        a.leafArray.map { it.name }.toList() == b.leafArray.map { it.name }.toList() &&
        a.colorTable.mapValues { it.value.name } == b.colorTable.mapValues { it.value.name } &&
        a.color.name == b.color.name &&
        a.maybeColor?.name == b.maybeColor?.name &&
        a.flags.map { it.name }.toSet() == b.flags.map { it.name }.toSet() &&
        a.maybeFlags?.map { it.name }?.toSet() == b.maybeFlags?.map { it.name }?.toSet() &&
        a.leaf.name == b.leaf.name &&
        a.otherText == b.otherText &&
        a.otherCount == b.otherCount &&
        a.message.toByteArray().contentEquals(b.message.toByteArray())

fun main() {
    // Records: every field kind, both directions. The leaf record compares with equals in both classes.
    val kotlin = kotlinEverything()
    check(sameJava(kotlin.toJava(), javaEverything()), "Kotlin -> Java")
    check(javaEverything().toKotlinJni() == kotlin, "Java -> Kotlin")
    check(kotlin.toJava().toKotlinJni() == kotlin, "Kotlin -> Java -> Kotlin")
    check(sameJava(javaEverything().toKotlinJni().toJava(), javaEverything()), "Java -> Kotlin -> Java")
    check(KotlinLeaf(7, "seven").toJava() == JavaLeaf(7, "seven"), "leaf Kotlin -> Java")
    check(JavaLeaf(7, "seven").toKotlinJni() == KotlinLeaf(7, "seven"), "leaf Java -> Kotlin")

    // Nested containers: list<list<R>> and map<string, map<string, R>>.
    val kotlinContainers = KotlinContainers(
        ArrayList(listOf(
            ArrayList(listOf(KotlinLeaf(40, "forty"), KotlinLeaf(41, "forty-one"))),
            ArrayList(listOf(KotlinLeaf(42, "forty-two"))))),
        HashMap(mapOf("outer" to HashMap(mapOf("inner" to KotlinLeaf(43, "forty-three"))))))
    val javaContainers = JavaContainers(
        ArrayList(listOf(
            ArrayList(listOf(JavaLeaf(40, "forty"), JavaLeaf(41, "forty-one"))),
            ArrayList(listOf(JavaLeaf(42, "forty-two"))))),
        HashMap(mapOf("outer" to HashMap(mapOf("inner" to JavaLeaf(43, "forty-three"))))))
    check(kotlinContainers.toJava() == javaContainers, "containers Kotlin -> Java")
    check(javaContainers.toKotlinJni() == kotlinContainers, "containers Java -> Kotlin")
    check(kotlinContainers.toJava().toKotlinJni() == kotlinContainers, "containers Kotlin -> Java -> Kotlin")
    check(javaContainers.toKotlinJni().toJava() == javaContainers, "containers Java -> Kotlin -> Java")

    // Enums and flags.
    check(KotlinColor.RED.toJava() == JavaColor.RED, "enum")
    check(JavaColor.BLUE.toKotlinJni() == KotlinColor.BLUE, "enum back")
    check(KotlinFlags.SECOND.toJava() == JavaFlags.SECOND, "flags")
    check(JavaFlags.FIRST.toKotlinJni() == KotlinFlags.FIRST, "flags back")

    // A Kotlin +j implementation behind the Java abstract class: every call is forwarded and converted.
    val kotlinImpl = KotlinListenerImpl()
    val javaListener = kotlinImpl.toJava()
    check(javaListener === kotlinImpl.toJava(), "one wrapper for one Kotlin object")
    check(javaListener.toKotlinJni() === kotlinImpl, "a wrapper round trip returns the Kotlin object")
    check(javaListener.value(1) == 2, "value")
    check(javaListener.optional(null) == null, "optional null")
    check(javaListener.optional(JavaLeaf(24, "twenty-four")) == "twenty-four", "optional")
    check(javaListener.list(ArrayList(listOf(JavaLeaf(25, "twenty-five")))) == ArrayList(listOf("twenty-five")), "list")
    check(javaListener.futureValue(1).get() == 2, "future value")
    check(javaListener.futureLeaf(JavaLeaf(26, "twenty-six")).get().name == "twenty-six", "future record")
    check(javaListener.futureOutcome(1).get().resultOr(null)?.name == "twenty", "future outcome value")
    check(javaListener.futureOutcome(0).get().errorOrNull()?.code == 9, "future outcome error")
    try {
        javaListener.failedLeafFuture().get()
        check(false, "the failed future must not return a value")
    } catch (error: ExecutionException) {
        check(failureMessage(error) == "failed future", "failed future error: $error")
    }
    check(javaListener.outcomeValue(1).resultOr(null)?.name == "twenty-one", "outcome value")
    check(javaListener.outcomeValue(0).errorOrNull()?.code == 9, "outcome error")
    check(javaListener.chain(javaListener, 1) == 3, "interface argument")
    check(javaListener.self() === javaListener, "interface return")
    check(javaListener.listeners(ArrayList(listOf(javaListener)))[0] === javaListener, "interface list")
    check(javaListener.maybeListener(null) == null, "interface optional null")
    check(javaListener.maybeListener(javaListener) === javaListener, "interface optional")
    check(javaListener.takeFuture(ready(JavaLeaf(50, "fifty"))).get() == "fifty", "future argument")
    check(javaListener.takeOutcome(Outcome.fromResult(JavaLeaf(51, "fifty-one"))) == "fifty-one", "outcome argument")

    // The cache releases a source that nothing else holds.
    val weakListener = weakListenerAfterConversion()
    val weakDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
    while (weakListener.get() != null && System.nanoTime() < weakDeadline) {
        System.gc()
        Thread.sleep(50)
    }
    check(weakListener.get() == null, "the wrapper cache releases the source")

    // A Java +j implementation behind the Kotlin abstract class.
    val javaImpl = JavaListenerImpl()
    val kotlinListener = javaImpl.toKotlinJni()
    check(kotlinListener === javaImpl.toKotlinJni(), "one wrapper for one Java object")
    check(kotlinListener.toJava() === javaImpl, "a wrapper round trip returns the Java object")
    check(kotlinListener.value(1) == 3, "reverse value")
    check(kotlinListener.optional(KotlinLeaf(27, "twenty-seven")) == "twenty-seven", "reverse optional")
    check(kotlinListener.list(ArrayList(listOf(KotlinLeaf(28, "twenty-eight")))) == ArrayList(listOf("twenty-eight")), "reverse list")
    check(kotlinListener.futureLeaf(KotlinLeaf(29, "twenty-nine")).get().mName == "twenty-nine", "reverse future")
    check(kotlinListener.futureOutcome(1).get().resultOr(null)?.mName == "twenty-two", "reverse future outcome")
    check(kotlinListener.outcomeValue(0).errorOrNull()?.mCode == 9, "reverse outcome")
    check(kotlinListener.chain(kotlinListener, 1) == 5, "reverse interface argument")
    check(kotlinListener.self() === kotlinListener, "reverse interface return")
    check(kotlinListener.takeFuture(ready(KotlinLeaf(52, "fifty-two"))).get() == "fifty-two", "reverse future argument")
    check(kotlinListener.takeOutcome(Outcome.fromResult(KotlinLeaf(53, "fifty-three"))) == "fifty-three", "reverse outcome argument")

    // A +c +j interface: each leg wraps the implementation of the other leg.
    val kotlinBoth = KotlinBothImpl()
    val javaBoth = kotlinBoth.toJava()
    check(javaBoth.ping(JavaLeaf(30, "thirty")).name == "thirty", "+c +j Kotlin to Java")
    check(javaBoth.toKotlinJni() === kotlinBoth, "+c +j Kotlin round trip")
    val javaBothImpl = JavaBothImpl()
    val kotlinBothOfJava = javaBothImpl.toKotlinJni()
    check(kotlinBothOfJava.ping(KotlinLeaf(31, "thirty-one")).mName == "thirty-one", "+c +j Java to Kotlin")
    check(kotlinBothOfJava.toJava() === javaBothImpl, "+c +j Java round trip")

    println("JAVA BRIDGE ROUND TRIP OK")
    System.exit(0)
}
