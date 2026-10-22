package djinni

import djinni.ast._
import djinni.generatorTools._

// Checks the Kotlin keys of the extern types before the JNI code binds them.
// The keys are kotlin.jniTypename for the Kotlin classes and jni.kotlinTranslator, jni.kotlinHeader and
// jni.kotlinTypeSignature for the JNI code. The Kotlin classes and the JNI code must agree on the class.
object KotlinJniExtern {
  private val keys = Seq("jni.kotlinTranslator", "jni.kotlinHeader", "jni.kotlinTypeSignature", "kotlin.jniTypename")

  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val keyed = idl.collect { case e: ExternTypeDecl if keys.exists(has(e, _)) => e }
    val incomplete = keyed.filterNot(e => keys.forall(has(e, _))).map { e =>
      s"extern type ${e.ident.name}: it needs all of ${keys.mkString(", ")}, or none of them"
    }
    val both = if (keyed.nonEmpty && spec.javaOutFolder.isDefined) {
      Seq("--java-out and --kotlin-jni-out with --jni-out bind one class for each extern type, " +
        s"but these extern types have Kotlin keys: ${keyed.map(_.ident.name).mkString(", ")}. " +
        "Run the generator twice, once with --java-out and once with --kotlin-jni-out.")
    } else Seq()
    val all = incomplete ++ both
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }

  // key is "<block>.<name>"
  private def has(e: ExternTypeDecl, key: String): Boolean = {
    val Array(block, name) = key.split('.')
    e.properties.get(block) match {
      case Some(map: java.util.Map[_, _]) => map.containsKey(name)
      case _ => false
    }
  }
}
