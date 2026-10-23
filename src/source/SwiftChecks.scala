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
    val swift = if (spec.swiftOutFolder.isDefined) reservedNameProblems(interns, spec) else Seq()
    if (swift.isEmpty) None else Some(swift.mkString("\n"))
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
