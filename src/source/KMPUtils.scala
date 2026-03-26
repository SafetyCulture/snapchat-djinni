package djinni

import generatorTools.Spec
import meta.Meta

class KMPUtils(kotlinMarshal: KotlinMarshal, spec: Spec) {

  def withPackage(packageName: Option[String], t: String): String = packageName.fold(t)(_ + "." + t)

  def withCInteropPackage(typeName: String): String = {
    spec.kotlinCInteropPackage.fold(typeName)(_ + "." + typeName)
  }

  def withSupportPackage(typeName: String): String = {
    spec.kotlinSupportPackage.fold(typeName)(_ + "." + typeName)
  }

  def generateTodo(tm: meta.MExpr): String = {
    def className(m: Meta) = m.getClass.getSimpleName.replace("$", "")

    val args = if (tm.args.isEmpty) "" else tm.args
      .map(kotlinMarshal.typename)
      .mkString("<", ", ", ">")

    generateTodo(s"Map: ${className(tm.base)}$args")
  }

  def generateTodo(s: String): String = {
    s"TODO(${'"'}$s${'"'})"
  }

  def throwUnsupported(s: String): String = {
    s"throw UnsupportedOperationException(${'"'}$s${'"'})"
  }
}
