package djinni

import meta._

import djinni.ast.{Enum, Interface, Record}
import djinni.generatorTools.{Spec, useProtocol}

import scala.collection.mutable

class KMPIOSObjcMapper(kotlinMarshal: KotlinMarshal, objcMarshal: ObjcMarshal, spec: Spec) {
  private val utils = new KMPUtils(spec)

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
        refs.add(utils.withSupportPackage("parseFromByteArray"))
        refs.add(utils.withCInteropPackage(objcMarshal.typename(m)))

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
          if(i.ext.objc) {
            s"${objcMarshal.typename(d.name, d.body)}Impl($valueName)"
          } else {
            utils.generateTodo(s"Impossible to map ${kotlinMarshal.typename(tm)} in this direction")
          }
        case _ => s"$valueName.toObjc()"
      }

      case e: MExtern =>
        if(e.kotlin.isProtobufMessage) {
          val objcType = objcMarshal.typename(tm)
          s"parseFromByteArray($valueName.encode(), $objcType::parseFromData)"
        } else {
          utils.generateTodo(s"Map external type: ${e.kotlin.typename}")
        }

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
              case _ => utils.generateTodo("Map boxed primitive type: " + p._idlName)
            }

          case d: MDef => d.body match {
            case _: Enum => s"$valueName?.toNSNumber()"
            case _: Record => s"$valueName?.toObjc()"
            case i: Interface =>
              if(i.ext.objc) {
                s"$valueName?.let { ${map("it", arg)} }"
              } else {
                utils.throwUnsupported(s"Impossible to map ${kotlinMarshal.typename(arg)} in this direction")
              }
            case _ => utils.generateTodo(tm.base)
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

      case _ => utils.generateTodo(tm.base)
    }
  }
}
