package djinni

import djinni.ast._
import djinni.ast.Record.DerivingType
import djinni.generatorTools._
import djinni.meta._

// Inputs that give Swift or Swift/C++ glue that does not compile. The checks run before any generator writes a file.
// Each message names the type, the member and the rule that the input breaks.
object SwiftChecks {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val interns = idl.collect { case d: InternTypeDecl => d }
    val swift = if (spec.swiftOutFolder.isDefined) codableProblems(interns) ++ reservedNameProblems(interns, spec) else Seq()
    if (swift.isEmpty) None else Some(swift.mkString("\n"))
  }

  private def subExprs(tm: MExpr): Seq[MExpr] = tm +: tm.args.flatMap(subExprs)

  // The generator adds Codable to enums, flags and records with deriving(codable). Swift cannot synthesize it for a
  // field of these types.
  private def codableProblems(interns: Seq[InternTypeDecl]): Seq[String] = {
    def notCodable(e: MExpr): Option[String] = e.base match {
      case d: MDef if d.defType == DInterface => Some(s"the interface ${d.name} is not Codable")
      case p: MProtobuf => Some(s"the protobuf message ${p.name} is not Codable")
      case x: MExtern if x.defType == DInterface || Set("outcome", "future", "DataRef", "DataView").contains(x.name) =>
        Some(s"the type ${x.name} is not Codable")
      case _ => None
    }
    for {
      td <- interns
      r <- Seq(td.body).collect { case r: Record if r.derivingTypes.contains(DerivingType.Codable) => r }
      f <- r.fields
      why <- subExprs(f.ty.resolved).flatMap(e => notCodable(e)).headOption
    } yield s"record ${td.ident.name}, field ${f.ident.name}: deriving(codable) needs a Codable type, but $why."
  }

  // The wrapper of --swift-async-wrap names its locals and members djinniXxx. An IDL name that Swift writes the same
  // way hides one of them.
  private def reservedNameProblems(interns: Seq[InternTypeDecl], spec: Spec): Seq[String] = {
    if (spec.swiftAsyncWrap.isEmpty) return Seq()
    val reserved = "djinni[A-Z].*".r
    for {
      td <- interns
      i <- Seq(td.body).collect { case i: Interface if i.ext.cpp && !i.ext.swift => i }
      m <- i.methods if !m.static
      (kind, name, swiftName) <- Seq(("method", m.ident.name, spec.swiftIdentStyle.method(m.ident.name))) ++
        m.params.map(p => ("parameter", p.ident.name, spec.swiftIdentStyle.local(p.ident.name)))
      if reserved.pattern.matcher(SwiftIdent.plain(swiftName)).matches
    } yield s"interface ${td.ident.name}, method ${m.ident.name}: the $kind name $name is $swiftName in Swift. --swift-async-wrap uses names that start with djinni and a capital letter inside the wrapper, so rename it."
  }
}
