package djinni

import ast.Interface

import djinni.generatorTools.Spec
import djinni.meta.Meta

class KMPUtils(spec: Spec) {
  // filter for supported interface methods
  def supportedMethods(i: Interface): Seq[Interface.Method] = {
    i.methods
    .filterNot(_.static) // no static method support
  }

  def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)

  def withCInteropPackage(typeName: String): String = {
    spec.kotlinCInteropPackage.fold(typeName)(_ + "." + typeName)
  }

  def withSupportPackage(typeName: String): String = {
    spec.kotlinSupportPackage.fold(typeName)(_ + "." + typeName)
  }

  def generateTodo(m: Meta): String = {
    generateTodo(m.getClass.getSimpleName.replace("$", ""))
  }

  def generateTodo(s: String): String = {
    s"TODO(${'"'}$s${'"'})"
  }

  def throwUnsupported(s: String): String = {
    s"throw UnsupportedOperationException(${'"'}$s${'"'})"
  }
}
