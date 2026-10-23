package djinni

import djinni.ast._
import djinni.generatorTools.Spec
import djinni.meta._

// Checks that every protobuf message and extern type that the IDL uses has the swift and
// swiftxx blocks, before any file is written. An extern yaml without them gets the literal
// "[unspecified]" for the Swift names, which the generators would emit into the output.
object SwiftProtobuf {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val refs = idl.flatMap(td => typeRefs(td.body)).flatMap(allTypes)
    val bases = refs.map(_.base)
    val missingProto = bases.collect { case p: MProtobuf if p.body.swift.isEmpty => p.name }.distinct
    val missingExtern = bases.collect {
      case e: MExtern if needsSwift(e, spec) || needsSwiftxx(e, spec) => e.name
    }.distinct
    val messages = missingProto.map(message) ++ missingExtern.map(externMessage)
    if (messages.isEmpty) None else Some(messages.mkString("\n"))
  }

  def message(name: String): String = s"Protobuf message $name has no 'swift' block in its manifest, but Swift output is enabled."

  def externMessage(name: String): String = s"Extern type $name has no 'swift'/'swiftxx' blocks in its manifest, but Swift output is enabled."

  private def unspecified(s: String): Boolean = s.isEmpty || s == "[unspecified]"

  // The Swift output names the type and the translator; both come from the swift block.
  private def needsSwift(e: MExtern, spec: Spec): Boolean =
    spec.swiftOutFolder.isDefined && (unspecified(e.swift.typename) || unspecified(e.swift.translator))

  // The Swift/C++ glue names the translator and its header; both come from the swiftxx block.
  private def needsSwiftxx(e: MExtern, spec: Spec): Boolean =
    spec.swiftxxOutFolder.isDefined && (unspecified(e.swiftxx.translator) || unspecified(e.swiftxx.header))

  private def typeRefs(body: TypeDef): Seq[TypeRef] = body match {
    case r: Record => r.fields.map(_.ty) ++ r.consts.map(_.ty)
    case i: Interface => i.methods.flatMap(m => m.params.map(_.ty) ++ m.ret) ++ i.consts.map(_.ty)
    case _ => Seq()
  }

  private def allTypes(ref: TypeRef): Seq[MExpr] = allTypes(ref.resolved)

  private def allTypes(tm: MExpr): Seq[MExpr] = tm +: tm.args.flatMap(allTypes)
}
