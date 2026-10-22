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

  private def methodProblem(marshal: SwiftMarshal, interface: String, m: Interface.Method, name: String): Option[String] = {
    val where = s"interface $interface, method ${m.ident.name}"
    val outcome = m.ret.map(_.resolved).flatMap { tm =>
      if (marshal.isOutcome(tm)) Some(tm)
      else if (marshal.isFuture(tm) && marshal.isOutcome(tm.args.head)) Some(tm.args.head)
      else None
    }
    outcome match {
      case None => Some(s"$where: --swift-error-type needs a return type outcome<T, $name>")
      case Some(tm) if marshal.isErrorRecord(tm.args(1), name) => None
      case Some(tm) if marshal.hasErrorName(tm.args(1), name) =>
        Some(s"$where: the error type $name is not a record")
      case Some(tm) =>
        Some(s"$where: the error type of the outcome is ${marshal.typename(tm.args(1))}, but --swift-error-type is $name")
    }
  }
}
