package djinni

import djinni.ast.Record.DerivingType
import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

// Checks the Kotlin keys of the extern types before the Kotlin classes and the JNI code use them.
// The keys are kotlin.jniTypename for the Kotlin classes and jni.kotlinTranslator, jni.kotlinHeader and
// jni.kotlinTypeSignature for the JNI code. The Kotlin classes and the JNI code must agree on the class.
object KotlinJniExtern {
  private val keys = Seq("jni.kotlinTranslator", "jni.kotlinHeader", "jni.kotlinTypeSignature", "kotlin.jniTypename")

  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    // The Kotlin classes alone do not need the JNI keys.
    val jniProblems = if (spec.jniOutFolder.isDefined) keyProblems(idl, spec) else Seq()
    val all = jniProblems ++ parcelerProblems(idl, spec)
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }

  def parcelerName(spec: Spec, fqn: String): String = spec.javaIdentStyle.ty(fqn.split('.').last) + "Parceler"

  // The Kotlin classes of the extern types that have kotlin.jniTypename, also as type arguments.
  def keyedExterns(tm: MExpr): Seq[String] =
    (tm.base match {
      case e: MExtern => e.kotlin.jniTypename.toSeq
      case _ => Seq()
    }) ++ tm.args.flatMap(keyedExterns)

  private def keyProblems(idl: Seq[TypeDecl], spec: Spec): Seq[String] = {
    val keyed = idl.collect { case e: ExternTypeDecl if keys.exists(has(e, _)) => e }
    val incomplete = keyed.filterNot(e => keys.forall(has(e, _))).map { e =>
      val missing = keys.filterNot(has(e, _))
      val verb = if (missing.size == 1) "is" else "are"
      s"extern type ${e.ident.name}: ${missing.mkString(", ")} $verb missing. Set all four Kotlin keys or none."
    }
    val both = if (keyed.nonEmpty && spec.javaOutFolder.isDefined) {
      Seq("--java-out and --kotlin-jni-out with --jni-out bind one class for each extern type, " +
        s"but these extern types have Kotlin keys: ${keyed.map(_.ident.name).mkString(", ")}. " +
        "Run the generator twice: --java-out with --jni-out, and --kotlin-jni-out with --jni-out.")
    } else Seq()
    incomplete ++ both
  }

  // Two Kotlin classes with the same simple name get the same Parceler name, and an IDL type can
  // collide with a Parceler name. Both cases fail here, before any file is written.
  private def parcelerProblems(idl: Seq[TypeDecl], spec: Spec): Seq[String] = {
    val classes = if (!spec.javaImplementAndroidOsParcelable) Seq() else idl.collect {
      case InternTypeDecl(_, _, r: Record, _, _) if r.derivingTypes.contains(DerivingType.AndroidParcelable) => r
    }.flatMap(_.fields.flatMap(f => keyedExterns(f.ty.resolved))).distinct
    val duplicate = classes.groupBy(parcelerName(spec, _)).toSeq.sortBy(_._1).collect {
      case (name, fqns) if fqns.size > 1 =>
        s"The classes ${fqns.mkString(" and ")} need a Parceler with the same name $name."
    }
    // Extern declarations write no Kotlin file, so only internal types can collide
    val typeNames = idl.collect { case d: InternTypeDecl => spec.javaIdentStyle.ty(d.ident.name) }.toSet
    val collision = classes.map(parcelerName(spec, _)).distinct.sorted.collect {
      case name if typeNames.contains(name) =>
        s"The Parceler name $name collides with an IDL type of the same name."
    }
    duplicate ++ collision
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
