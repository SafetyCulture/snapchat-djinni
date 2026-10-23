package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

// Checks --swift-error-type. Every method that Swift calls into C++ throws the error type: the instance methods of an
// interface with +c and without +sw, and the static methods of an interface with +c.
object SwiftErrorType {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val name = spec.swiftErrorType.get
    val marshal = new SwiftMarshal(spec)
    val problems = for {
      td <- idl
      i <- td.body match { case i: Interface => Seq(i); case _ => Seq() }
      if i.ext.cpp
      m <- i.methods if affected(i, m)
      problem <- methodProblem(marshal, spec, td.ident.name, m, name)
    } yield problem
    val missing = if (idl.exists(td => isErrorRecord(spec, td, name))) Seq() else Seq(s"--swift-error-type $name: no record has this Swift name")
    val all = missing ++ problems
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }

  // The host implements the protocol of an interface with +sw, so its instance methods keep the untyped form.
  def affected(i: Interface, m: Interface.Method): Boolean =
    i.ext.cpp && (if (m.static) m.lang.swift else !i.ext.swift)

  private def isErrorRecord(spec: Spec, td: TypeDecl, name: String): Boolean = td match {
    case _: InternTypeDecl => td.body.isInstanceOf[Record] && spec.swiftIdentStyle.ty(td.ident.name) == name
    case e: ExternTypeDecl => e.body.isInstanceOf[Record] && swiftTypename(e).contains(name)
    case _ => false
  }

  private def swiftTypename(e: ExternTypeDecl): Option[String] = e.properties.get("swift") match {
    case Some(block: java.util.Map[_, _]) => Option(block.get("typename")).map(_.toString)
    case _ => None
  }

  // An extern type without a Swift name is shown with its IDL name.
  private def found(marshal: SwiftMarshal, tm: MExpr): String = tm.base match {
    case e: MExtern if e.swift.typename.isEmpty || e.swift.typename == "[unspecified]" => s"${e.name} (it has no Swift name)"
    case _ => marshal.typename(tm)
  }

  private def outcomeProblem(marshal: SwiftMarshal, where: String, o: MExpr, name: String): Option[String] = {
    if (marshal.isErrorRecord(o.args(1), name)) None
    else if (marshal.hasErrorName(o.args(1), name)) Some(s"$where: the error type $name is not a record")
    else Some(s"$where: the error type of the outcome is ${found(marshal, o.args(1))}, but --swift-error-type is $name")
  }

  private def methodProblem(marshal: SwiftMarshal, spec: Spec, interface: String, m: Interface.Method, name: String): Seq[String] = {
    val where = s"interface $interface, method ${m.ident.name}"
    m.ret.map(_.resolved) match {
      case Some(tm) if marshal.isFuture(tm) =>
        // The async form of a future needs the queue and the cancellation of the async wrapper
        val wrap = if (spec.swiftAsyncWrap.isEmpty) Seq(s"$where: --swift-error-type needs --swift-async-wrap for a return type future<>") else Seq()
        val inner = if (marshal.isOutcome(tm.args.head)) outcomeProblem(marshal, where, tm.args.head, name).toSeq else Seq()
        wrap ++ inner
      case Some(tm) if marshal.isOutcome(tm) => outcomeProblem(marshal, where, tm, name).toSeq
      case _ => Seq()
    }
  }
}
