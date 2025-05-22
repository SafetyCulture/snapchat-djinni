package djinni

import meta._

import scala.collection.mutable

class KMPIOSObjcMapper() {

  def typeRefs(m: MExpr): Set[String] = {
    val refs = mutable.Set[String]()

    m.base match {
      case MOptional => refs ++= typeRefs(m.args.head)
      case MList => refs ++= typeRefs(m.args.head)
      case MDate => refs.add("kotlinx.datetime.toNSDate")
      case _ =>
    }

    return refs.toSet
  }

  def map(valueName: String, tm: MExpr, optional: Boolean = false): String = {
    tm.base match {
      case _: MPrimitive | MString => valueName
      case MDate => s"$valueName.toNSDate()"

      case MList => s"ArrayList($valueName.map { " + map("it", tm.args.head) + " })"

      //      case MMap =>
      //        val key = tm.args.head.base
      //        val value = tm.args.last.base
      //        (key, value) match {
      //          case (_: MPrimitive, _: MPrimitive) |
      //               (MString, _: MPrimitive) |
      //               (_: MPrimitive, MString) |
      //               (MString, MString) => s"$valueName.toMap(HashMap())"
      //
      //          case (_: MPrimitive, _) |
      //               (MString, _) => s"$valueName.mapValues { ${map("it.value", tm.args.last)} }.toMap(HashMap())"
      //
      //          case _ => s"$valueName.map { (k, v) -> ${map("k", tm.args.head)} to ${map("v", tm.args.last)}) }.toMap(HashMap())"
      //        }

      case d: MDef => d.defType match {
        case DEnum => s"$valueName.toObjc()"
        case DRecord => s"$valueName.toObjc()"
        case DInterface => generateTodo(d)
      }

      //      case e: MExtern if e.kotlin.isProtobufMessage =>
      //        val objcType = objcMarshal.typename(tm)
      //        s"$objcType.parseFromData($valueName.encode().toData(), null)"
      //      case e: MExtern =>
      //        throw new AssertionError("map called on extern type which isn't a protobuf message")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg)
          case d: MDef if d.defType == DEnum => s"$valueName?.toNSNumber()"
          case MList => s"$valueName?.let { list -> " + map("list", tm.args.head) + " }"
          case _ => map(s"$valueName?", arg)
        }

      case _ => generateTodo(tm.base)
    }
  }

  def generateTodo(m: Meta): String = {
    s"TODO(${'"'}Map ${m.getClass.getSimpleName.replace("$", "")} to ObjC${'"'})"
  }
}
