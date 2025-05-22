package djinni

import meta._

import djinni.generatorTools.Spec

import scala.collection.mutable

class KMPIOSObjcMapper(objcMarshal: ObjcMarshal, spec: Spec) {

  def typeRefs(m: MExpr): Set[String] = {
    val refs = mutable.Set[String]()

    m.base match {
      case MOptional => refs ++= typeRefs(m.args.head)
      case MList => refs ++= typeRefs(m.args.head)
      case MDate => refs.add("kotlinx.datetime.toNSDate")
      case e: MExtern if e.kotlin.isProtobufMessage =>
        refs.add(withSupportPackage("parseFromByteArray"))
        refs.add(withCInteropPackage(objcMarshal.typename(m)))

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

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val objcType = objcMarshal.typename(tm)
        s"parseFromByteArray($valueName.encode(), $objcType::parseFromData)"

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg)
          case d: MDef if d.defType == DEnum => s"$valueName?.toNSNumber()"
          case _: MExtern => s"$valueName?.let { ${map("it", arg)} }"
          case MList => s"$valueName?.let { list -> " + map("list", tm.args.head) + " }"
          case _ => map(s"$valueName?", arg)
        }

      case _ => generateTodo(tm.base)
    }
  }

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
}
