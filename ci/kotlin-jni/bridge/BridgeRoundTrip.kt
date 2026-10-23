// Round trips every field kind between the Java classes of one generator run and the Kotlin JNI classes of another.

import com.dropbox.djinni.bridgejava.KotlinJavaBridgeColor as JavaColor
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeError as JavaError
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeEverything as JavaEverything
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeFlags as JavaFlags
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeLeaf as JavaLeaf
import com.dropbox.djinni.bridgejava.KotlinJavaBridgeListener as JavaListener
import com.dropbox.djinni.bridgekt.KotlinJavaBridgeColor as KotlinColor
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

private fun kotlinLeaf(): KotlinLeaf = KotlinLeaf(7, "seven")

private fun javaLeaf(): JavaLeaf = JavaLeaf(7, "seven")

private fun kotlinEverything(): KotlinEverything = KotlinEverything(
    true, 8, 16, 32, 64, 1.5f, 2.5, "text", byteArrayOf(1, 2, 3), Date(1_700_000_000_000L),
    5, null, kotlinLeaf(), ArrayList(listOf(kotlinLeaf())), ArrayList(listOf("name")),
    HashSet(listOf("key")), HashMap(mapOf("table" to kotlinLeaf())),
    HashMap(mapOf("nested" to ArrayList(listOf(kotlinLeaf())))),
    KotlinColor.GREEN, null, EnumSet.of(KotlinFlags.FIRST, KotlinFlags.THIRD), null,
    kotlinLeaf(), ExternKotlinMessage(byteArrayOf(9, 8)))

private fun javaEverything(): JavaEverything = JavaEverything(
    true, 8, 16, 32, 64, 1.5f, 2.5, "text", byteArrayOf(1, 2, 3), Date(1_700_000_000_000L),
    5, null, javaLeaf(), ArrayList(listOf(javaLeaf())), ArrayList(listOf("name")),
    HashSet(listOf("key")), HashMap(mapOf("table" to javaLeaf())),
    HashMap(mapOf("nested" to ArrayList(listOf(javaLeaf())))),
    JavaColor.GREEN, null, EnumSet.of(JavaFlags.FIRST, JavaFlags.THIRD), null,
    javaLeaf(), ExternJavaMessage(byteArrayOf(9, 8)))

private class KotlinListenerImpl : KotlinListener() {
    override fun value(value: Int): Int = value + 1

    override fun optional(leaf: KotlinLeaf?): String? = leaf?.mName

    override fun list(items: ArrayList<KotlinLeaf>): ArrayList<String> = ArrayList(items.map { it.mName })

    override fun futureValue(value: Int): Future<Int> = ready(value + 1)

    override fun futureLeaf(leaf: KotlinLeaf): Future<KotlinLeaf> = ready(leaf)

    override fun outcomeValue(value: Int): Outcome<KotlinLeaf, KotlinError> =
        if (value > 0) Outcome.fromResult(kotlinLeaf()) else Outcome.fromError(KotlinError("failed", 9))
}

private class JavaListenerImpl : JavaListener() {
    override fun value(value: Int): Int = value + 2

    override fun optional(leaf: JavaLeaf?): String? = leaf?.name

    override fun list(items: ArrayList<JavaLeaf>): ArrayList<String> = ArrayList(items.map { it.name })

    override fun futureValue(value: Int): Future<Int> = ready(value + 2)

    override fun futureLeaf(leaf: JavaLeaf): Future<JavaLeaf> = ready(leaf)

    override fun outcomeValue(value: Int): Outcome<JavaLeaf, JavaError> =
        if (value > 0) Outcome.fromResult(javaLeaf()) else Outcome.fromError(JavaError("failed", 9))
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
        a.color.name == b.color.name &&
        a.maybeColor?.name == b.maybeColor?.name &&
        a.flags.map { it.name }.toSet() == b.flags.map { it.name }.toSet() &&
        a.maybeFlags?.map { it.name }?.toSet() == b.maybeFlags?.map { it.name }?.toSet() &&
        a.leaf.name == b.leaf.name &&
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
    check(javaListener.optional(javaLeaf()) == "seven", "optional")
    check(javaListener.list(ArrayList(listOf(javaLeaf()))) == ArrayList(listOf("seven")), "list")
    check(javaListener.futureValue(1).get() == 2, "future value")
    check(javaListener.futureLeaf(javaLeaf()).get().name == "seven", "future record")
    check(javaListener.outcomeValue(1).resultOr(null)?.name == "seven", "outcome value")
    check(javaListener.outcomeValue(0).errorOrNull()?.code == 9, "outcome error")

    // A Java +j implementation behind the Kotlin abstract class.
    val javaImpl = JavaListenerImpl()
    val kotlinListener = javaImpl.toKotlinJni()
    check(kotlinListener === javaImpl.toKotlinJni(), "one wrapper for one Java object")
    check(kotlinListener.toJava() === javaImpl, "a wrapper round trip returns the Java object")
    check(kotlinListener.value(1) == 3, "reverse value")
    check(kotlinListener.optional(kotlinLeaf()) == "seven", "reverse optional")
    check(kotlinListener.list(ArrayList(listOf(kotlinLeaf()))) == ArrayList(listOf("seven")), "reverse list")
    check(kotlinListener.futureLeaf(kotlinLeaf()).get().mName == "seven", "reverse future")
    check(kotlinListener.outcomeValue(0).errorOrNull()?.mCode == 9, "reverse outcome")

    println("JAVA BRIDGE ROUND TRIP OK")
    System.exit(0)
}
