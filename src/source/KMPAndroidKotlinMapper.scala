package djinni

import ast.Interface
import generatorTools.Spec
import meta._

class KMPAndroidKotlinMapper(kotlinMarshal: KotlinMarshal, spec: Spec) {
 private val utils = new KMPUtils(kotlinMarshal, spec)

  def map(valueName: String, tm: MExpr, optional: Boolean = false): String = {
    val unwrap = if (optional) "?" else ""
    tm.base match {
      case _: MPrimitive | MString => valueName
      case MDate => s"Instant.fromEpochMilliseconds($valueName.time)"
      case MMap =>
        val key = tm.args.head.base
        val value = tm.args.last.base
        (key, value) match {
          case (_: MPrimitive, _: MPrimitive) |
               (MString, _: MPrimitive) |
               (_: MPrimitive, MString) |
               (MString, MString) => s"$valueName.toMap()"

          case (_: MPrimitive, _) |
               (MString, _) => s"$valueName.mapValues { ${map("it.value", tm.args.last)} }"
          case _ =>
            s"$valueName.map { (k, v) -> ${map("k", tm.args.head)} to ${map("v", tm.args.last)} }$unwrap.toMap()"
        }

      case MSet =>
        val setType = tm.args.head
        setType.base match {
          case _: MPrimitive | MString => valueName
          case m: MDef if (m.defType == DEnum) => s"$valueName.map { ${map("it", setType)} }$unwrap.toSet()"
          case _ => utils.generateTodo(tm)
        }

      case d: MDef => d.body match {
        case i: Interface =>
          if (i.ext.cpp) {
            s"$valueName?.let { ${kotlinMarshal.typename(tm)}Impl(it) }"
          } else {
            utils.throwUnsupported(s"Impossible to map ${kotlinMarshal.typename(tm)} in this direction")
          }
        case _ =>s"$valueName.toKotlin()"
      }

      case MList =>
        s"$valueName.map { " + map("it", tm.args.head) + " }"

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val kotlinType = kotlinMarshal.fqTypename(tm)
        s"$kotlinType.ADAPTER.decode($valueName.toByteArray())"

      case e: MExtern =>
        utils.generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg, optional = true)
          case MDate | _: MExtern => s"$valueName?.let { ${map("it", arg, optional = true)} }"
          case MDef(_, _, _, _: Interface) => map(s"$valueName", arg, optional = true)
          case _ => map(s"$valueName?", arg, optional = true)
        }

      case _ => utils.generateTodo(tm)
    }
  }
}
