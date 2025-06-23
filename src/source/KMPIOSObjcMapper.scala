package djinni

import meta._

import djinni.ast.{Interface, Record}
import djinni.generatorTools.{Spec, useProtocol}

import scala.collection.mutable

class KMPIOSObjcMapper(objcMarshal: ObjcMarshal, spec: Spec) {

  def typeRefs(m: MExpr): Set[String] = {
    val refs = mutable.Set[String]()

    m.base match {
      case MOptional =>
        // special cases
        m.args.head.base match {
          case _: MPrimitive =>
            refs.add("platform.Foundation.NSNumber")
          case _ =>
        }

        // evaluate optional type
        refs ++= typeRefs(m.args.head)

      case MList | MSet => refs ++= typeRefs(m.args.head)
      case MMap => refs ++= typeRefs(m.args.head) ++ typeRefs(m.args.last)
      case MDate => refs.add("kotlinx.datetime.toNSDate")
      case e: MExtern if e.kotlin.isProtobufMessage =>
        refs.add(withSupportPackage("parseFromByteArray"))
        refs.add(withCInteropPackage(objcMarshal.typename(m)))

      case _ =>
    }

    return refs.toSet
  }

  def map(valueName: String, tm: MExpr): String = {
    tm.base match {
      case _: MPrimitive | MString => valueName
      case MDate => s"$valueName.toNSDate()"

      case MList => s"ArrayList($valueName.map { " + map("it", tm.args.head) + " })"

      case MSet =>
        s"$valueName.map { ${map("it", tm.args.head)} }.toSet()"

      case MMap =>
        val key = tm.args.head
        val value = tm.args.last

        // primitive key / value case
        s"$valueName.map { ${map("it.key", key)} to ${map("it.value", value)} }.toMap()"


      case d: MDef => d.body match {
        case i: Interface =>
          if(useProtocol(i.ext, spec)) {
            s"${objcMarshal.typename(d.name, d.body)}Impl($valueName)"
          } else {
            generateTodo(s"Map: ${objcMarshal.typename(tm)}")
          }
        case _ => s"$valueName.toObjc()"
      }

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val objcType = objcMarshal.typename(tm)
        s"parseFromByteArray($valueName.encode(), $objcType::parseFromData)"

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case MString => map(s"$valueName", arg)
          case p: MPrimitive =>
            p._idlName match {
              case "bool" => s"$valueName?.let { NSNumber(bool = it) }"
              case "i8" => s"$valueName?.let { NSNumber(char = it) }"
              case "i16" => s"$valueName?.let { NSNumber(short = it) }"
              case "i32" => s"$valueName?.let { NSNumber(int = it) }"
              case "i64" => s"$valueName?.let { NSNumber(long = it) }"
              case "f32" => s"$valueName?.let { NSNumber(float = it) }"
              case "f64" => s"$valueName?.let { NSNumber(double = it) }"
              case _ => generateTodo("Map boxed primitive type: " + p._idlName)
            }

          case d: MDef => d.defType match {
            case DEnum => s"$valueName?.toNSNumber()"
            case DRecord => s"$valueName?.toObjc()"
            case DInterface => s"$valueName?.let { ${map("it", arg)} }"
          }

          case _: MExtern => s"$valueName?.let { ${map("it", arg)} }"
          case MList => s"$valueName?.let { list -> " + map("list", arg) + " }"
          case MSet => s"$valueName?.map { set -> " + map("set", arg.args.head) + " }?.toSet()"
          case MMap =>
            val key = arg.args.head
            val value = arg.args.last
            // primitive key / value case
            s"$valueName?.map { ${map("it.key", key)} to ${map("it.value", value)} }?.toMap()"
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
