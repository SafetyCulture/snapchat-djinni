package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

// Checks --swift-sync-method. The async wrapper gives a synchronous form only to the listed methods, and only when
// the form can call C++ on the thread of the caller.
object SwiftSyncMethods {
  // The Swift name of the synchronous form. A keyword name has backticks, and `default`Now is not a name.
  def syncName(ident: IdentConverter, m: Interface.Method): String = ident(m.ident.name).replace("`", "") + "Now"

  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val marshal = new SwiftMarshal(spec)
    val problems = spec.swiftSyncMethods.distinct.flatMap(value => problem(idl, spec, marshal, value))
    if (problems.isEmpty) None else Some(problems.mkString("\n"))
  }

  private def problem(idl: Seq[TypeDecl], spec: Spec, marshal: SwiftMarshal, value: String): Seq[String] = value.split("\\.", 2) match {
    case Array(interface, method) if interface.nonEmpty && method.nonEmpty =>
      interfaceProblem(idl, spec, marshal, value, interface, method)
    case _ => Seq(s"--swift-sync-method $value: the value needs the form <interface>.<method>.")
  }

  private def interfaceProblem(idl: Seq[TypeDecl], spec: Spec, marshal: SwiftMarshal,
                               value: String, interface: String, method: String): Seq[String] = {
    val body = idl.collectFirst { case td: InternTypeDecl if td.ident.name == interface => td.body }
    body match {
      case Some(i: Interface) => methodProblem(spec, marshal, value, interface, i, method)
      case Some(_) => Seq(s"--swift-sync-method $value: $interface is not an interface.")
      case None => Seq(s"--swift-sync-method $value: there is no interface $interface.")
    }
  }

  private def methodProblem(spec: Spec, marshal: SwiftMarshal, value: String, interface: String,
                            i: Interface, method: String): Seq[String] = {
    i.methods.find(_.ident.name == method) match {
      case None => Seq(s"--swift-sync-method $value: interface $interface has no method $method.")
      case Some(m) =>
        val wrapped = i.ext.cpp && !i.ext.swift
        val name = syncName(spec.swiftIdentStyle.method, m)
        val collision = i.methods.find(other => other.ident.name != m.ident.name && spec.swiftIdentStyle.method(other.ident.name) == name)
        val problems = Seq(
          Some(s"--swift-sync-method $value: the async wrapper has no class for interface $interface, because it is not an interface with +c and without +sw.")
            .filter(_ => !wrapped),
          Some(s"--swift-sync-method $value: $interface.$method is static, and the async wrapper has no static methods.")
            .filter(_ => m.static),
          Some(s"--swift-sync-method $value: $interface.$method returns future<>, and a synchronous form cannot wait for a future.")
            .filter(_ => m.ret.exists(r => marshal.isFuture(r.resolved))),
          collision.map(other => s"--swift-sync-method $value: the synchronous form $name equals the name of the method ${other.ident.name} of interface $interface.")
        )
        problems.flatten
    }
  }
}
