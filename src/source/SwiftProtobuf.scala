package djinni

import djinni.ast._
import djinni.meta._

// Checks that every protobuf message that the IDL uses has a swift block, before any file is written.
object SwiftProtobuf {
  def check(idl: Seq[TypeDecl]): Option[String] = {
    val missing = idl.flatMap(td => typeRefs(td.body)).flatMap(ref => protobufs(ref.resolved)).filter(_.body.swift.isEmpty).map(_.name).distinct
    if (missing.isEmpty) None
    else Some(missing.map(name => message(name)).mkString("\n"))
  }

  def message(name: String): String = s"Protobuf message $name has no 'swift' block in its manifest, but Swift output is enabled."

  private def typeRefs(body: TypeDef): Seq[TypeRef] = body match {
    case r: Record => r.fields.map(_.ty) ++ r.consts.map(_.ty)
    case i: Interface => i.methods.flatMap(m => m.params.map(_.ty) ++ m.ret) ++ i.consts.map(_.ty)
    case _ => Seq()
  }

  private def protobufs(tm: MExpr): Seq[MProtobuf] = {
    val own = tm.base match { case p: MProtobuf => Seq(p); case _ => Seq() }
    own ++ tm.args.flatMap(protobufs)
  }
}
