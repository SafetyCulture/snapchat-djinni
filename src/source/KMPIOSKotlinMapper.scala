package djinni

import meta._

import scala.collection.mutable

class KMPIOSKotlinMapper(marshal: KotlinMarshal) {

  def typeRefs(m: MExpr): Set[String] = {
    val refs = mutable.Set[String]()
    m.base match {
      case MOptional =>
        // unwrap optional type
        refs ++= typeRefs(m.args.head)

      case MList =>
        // special cases for list types
        m.args.head.base match {
          case MDate =>
            // will need to cast the list type to NSDate
            refs.add("platform.Foundation.NSDate")
          case _ =>
        }

        // unwrap list item type
        refs ++= typeRefs(m.args.head)

      case MDate =>
        refs.add("kotlinx.datetime.toKotlinInstant")

      case _ =>
    }

    return refs.toSet
  }

  def map(valueName: String, tm: MExpr): String = {
    tm.base match {
      case _: MPrimitive | MString => valueName
      case MDate => s"$valueName.toKotlinInstant()"
      case MList =>
        val listType = tm.args.head
        val castType = listType.base match {
          case MDate => "NSDate"
          case d: MDef =>
            d.defType match {
              case DEnum => "Long"
              case _ => generateTodo(d)
            }
          case _ => marshal.typename(listType)
        }
        val listValueName = listType.base match {
          case MDate => s"(it as ${castType})"
          case _ => s"it as ${castType}"
        }
        s"$valueName.map { " + map(s"${listValueName}", listType) + " }"

      //      case MMap =>
      //        val key = tm.args.head.base
      //        val value = tm.args.last.base
      //        (key, value) match {
      //        case (_: MPrimitive, _: MPrimitive) |
      //             (MString, _: MPrimitive) |
      //             (_: MPrimitive, MString) |
      //             (MString, MString) => s"$valueName.toMap()"
      //
      //        case (_: MPrimitive, _) |
      //             (MString, _) => s"$valueName.mapValues { ${map("it.value", tm.args.last)} }"
      //
      //        case _ => s"$valueName.map { (k, v) -> ${map("k", tm.args.head)} to ${map("v", tm.args.last)}) }.toMap()"
      //      }

      case d: MDef => d.defType match {
        case DEnum => s"${marshal.typename(tm)}.fromObjc($valueName)"
        case DRecord => s"$valueName.toKotlin()"
        case DInterface => generateTodo(d)
      }

      case MList =>
        s"$valueName.map { " + map("it", tm.args.head) + " }"

      //      case e: MExtern if e.kotlin.isProtobufMessage =>
      //        val kotlinType = e.kotlin.typename
      //        s"$valueName.data()?.let { $kotlinType.ADAPTER.decode(it.toByteArray()) }"

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case _: MPrimitive | MString => map(s"$valueName", arg)
          case d: MDef if d.defType == DEnum => s"$valueName?.let { ${marshal.typename(arg)}.fromNSNumber(it) }"
          case _ => map(s"$valueName?", arg)
        }

      case _ => generateTodo(tm.base)
    }
  }

  def generateTodo(m: Meta): String = {
    s"TODO(${'"'}Map ${m.getClass.getSimpleName.replace("$", "")} to Kotlin${'"'})"
  }
}
