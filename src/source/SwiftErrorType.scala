package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

// Checks --swift-error-type: every instance method of a C++ interface returns outcome<T, E>.
object SwiftErrorType {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val name = spec.swiftErrorType.get
    val marshal = new SwiftMarshal(spec)
    val problems = for {
      td <- idl
      i <- td.body match { case i: Interface => Seq(i); case _ => Seq() }
      if i.ext.cpp
      m <- i.methods if !m.static
      problem <- methodProblem(marshal, td.ident.name, m, name)
    } yield problem
    val missing = if (idl.exists(td => isErrorRecord(spec, td, name))) Seq() else Seq(s"--swift-error-type $name: no record has this Swift name")
    val all = missing ++ problems
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }

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

  private def methodProblem(marshal: SwiftMarshal, interface: String, m: Interface.Method, name: String): Option[String] = {
    val where = s"interface $interface, method ${m.ident.name}"
    m.ret.map(_.resolved) match {
      // A future of an outcome has two error channels and no place for a cancellation; reject it
      case Some(tm) if marshal.isFuture(tm) && marshal.isOutcome(tm.args.head) =>
        Some(s"$where: --swift-error-type does not support a return type future<outcome<T, ${found(marshal, tm.args.head.args(1))}>>")
      case Some(tm) =>
        val outcome = if (marshal.isOutcome(tm)) Some(tm) else None
        outcome match {
          case None => Some(s"$where: --swift-error-type needs a return type outcome<T, $name>")
          case Some(o) if marshal.isErrorRecord(o.args(1), name) => None
          case Some(o) if marshal.hasErrorName(o.args(1), name) =>
            Some(s"$where: the error type $name is not a record")
          case Some(o) =>
            Some(s"$where: the error type of the outcome is ${found(marshal, o.args(1))}, but --swift-error-type is $name")
        }
      case None => Some(s"$where: --swift-error-type needs a return type outcome<T, $name>")
    }
  }
}
