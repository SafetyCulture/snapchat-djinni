package djinni

import djinni.ast._
import djinni.generatorTools._

// --kotlin-error-type changes each method that Kotlin calls into C++: the instance methods of an interface with +c
// and without +j, and the static methods. The JNI code calls the methods of an interface with +j by their
// signature, so those keep the raw form.
object KotlinErrorType {
  def affected(i: Interface, m: Interface.Method): Boolean =
    if (m.static) m.lang.java else i.ext.cpp && !i.ext.java

  // Checks the flag before a file is written. A future needs a suspend function, and the class has one
  // constructor (error: E), so all outcomes must have the same E.
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val name = spec.kotlinErrorType.get
    val marshal = new KotlinJniMarshal(spec)
    val methods = for {
      td <- idl.collect { case t: InternTypeDecl => t }
      i <- td.body match { case i: Interface => Seq(i); case _ => Seq() }
      m <- i.methods if affected(i, m)
    } yield (s"interface ${td.ident.name}, method ${m.ident.name}", m.ret.map(_.resolved))
    val futures = if (spec.kotlinSuspendWrap) Seq() else methods.collect {
      case (where, Some(tm)) if marshal.futureArg(tm).isDefined =>
        s"$where: --kotlin-error-type needs --kotlin-suspend-wrap for a method that returns future<T>"
    }
    val errors = methods.flatMap { case (where, ret) =>
      ret.flatMap(tm => marshal.outcomeTypes(marshal.futureArg(tm).getOrElse(tm))).map { case (_, e) => (e, where) }
    }
    // Each error type with the first method that uses it
    val distinct = errors.foldLeft(Seq[(String, String)]())((seen, e) => if (seen.exists(_._1 == e._1)) seen else seen :+ e)
    val mixed = if (distinct.size <= 1) Seq() else Seq(
      s"--kotlin-error-type $name has one constructor (error: E), but the outcomes have ${distinct.size} error types: " +
        distinct.map { case (e, where) => s"$e ($where)" }.mkString(", "))
    val all = futures ++ mixed
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }
}
