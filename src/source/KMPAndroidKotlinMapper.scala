package djinni

import generatorTools.Spec
import meta._

import scala.collection.mutable

class KMPAndroidKotlinMapper(kotlinMarshal: KotlinMarshal) {
  def map(valueName: String, tm: MExpr, optional: Boolean = false): String = {
    val unwrap = if (optional) "?" else ""
    tm.base match {
      case _: MPrimitive => valueName
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
          case _ => generateTodo(tm.base)
        }

      case d: MDef => d.defType match {
        case DEnum | DRecord => s"$valueName.toKotlin()"
        case DInterface => generateTodo(tm.base)
      }

      case MList =>
        s"$valueName.map { " + map("it", tm.args.head) + " }"

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val kotlinType = kotlinMarshal.fqTypename(tm)
        s"$kotlinType.ADAPTER.decode($valueName.toByteArray())"

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg, optional = true)
          case MDate | _: MExtern => s"$valueName?.let { ${map("it", arg, optional = true)} }"
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
