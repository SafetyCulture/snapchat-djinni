package djinni

import ast.Interface
import generatorTools.Spec
import meta._

class KMPAndroidJavaMapper(javaMarshal: JavaMarshal, spec: Spec) {
  private val utils = new KMPUtils(spec)

  def map(valueName: String, tm: MExpr, optional: Boolean = false): String = {
    tm.base match {
      case _: MPrimitive => valueName
      case MDate => s"Date($valueName.toEpochMilliseconds())"

      case MMap =>
        val key = tm.args.head.base
        val value = tm.args.last.base
        val unwrap = if (optional) "?" else ""
        (key, value) match {
          case (_: MPrimitive, _: MPrimitive) |
               (MString, _: MPrimitive) |
               (_: MPrimitive, MString) |
               (MString, MString) => s"$valueName.toMap(HashMap())"

          case (_: MPrimitive, _) |
               (MString, _) =>
            s"$valueName.mapValues { ${map("it.value", tm.args.last)} }$unwrap.toMap(HashMap())"

          case _ => s"$valueName.map { (k, v) -> ${map("k", tm.args.head)} to ${map("v", tm.args.last)} }$unwrap.toMap(HashMap())"
        }

      case MSet =>
        val setType = tm.args.head
        setType.base match {
          case _: MPrimitive | MString => s"HashSet(${map(valueName, setType)})"
          case m: MDef if (m.defType == DEnum) => s"HashSet($valueName.map { ${map("it", setType)} })"
          case _ => generateTodo(tm.base)
        }

      case m: MDef => m.body match {
        case i: Interface =>
          if (i.ext.java) {
            s"${javaMarshal.typename(tm)}Impl($valueName)"
          } else {
            utils.throwUnsupported(s"Impossible to map ${javaMarshal.typename(tm)} in this direction")
          }
        case _ => s"$valueName.toJava()"
      }

      case MList =>
        s"ArrayList($valueName.map { " + map("it", tm.args.head) + " })"

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val javaType = javaMarshal.fqTypename(tm)
        s"$javaType.parseFrom($valueName.encode())"

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg, optional = true)
          case MDate | _: MExtern  => s"$valueName?.let { ${map("it", arg, optional = true)} }"
          case MList => s"$valueName?.let { list -> ${map("list", arg, optional = true)} }"
          case MSet => s"$valueName?.let { set -> ${map("set", arg, optional = true)} }"
          case MDef(_, _, _, _: Interface) => s"$valueName?.let { ${map(s"it", arg, optional = true)} }"
          case _ => map(s"$valueName?", arg, optional = true)
        }

      case _ => valueName
    }
  }

  def generateTodo(m: Meta): String = {
    generateTodo(m.getClass.getSimpleName.replace("$", ""))
  }

  def generateTodo(s: String): String = {
    s"TODO(${'"'}$s${'"'})"
  }
}
