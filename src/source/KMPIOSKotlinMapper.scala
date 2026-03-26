package djinni

import ast.{Enum, Interface, Record}
import generatorTools.Spec
import meta._

import scala.collection.mutable

class KMPIOSKotlinMapper(kotlinMarshal: KotlinMarshal, objcMarshal: ObjcMarshal, spec: Spec) {
  private val utils = new KMPUtils(kotlinMarshal, spec)

  def typeRefs(m: MExpr, requiresCast: Boolean = false): Set[String] = {
    val refs = mutable.Set[String]()
    m.base match {
      case MOptional =>
        // evaluate optional type
        refs ++= typeRefs(m.args.head, requiresCast = true)

      case MList | MSet =>
        // special cases for list / set types
        m.args.head.base match {
          case MDate =>
            // will need to cast the list / set type to NSDate
            refs.add("platform.Foundation.NSDate")
          case _ =>
        }

        // evaluate list / set type
        refs ++= typeRefs(m.args.head, requiresCast = true)

      case MMap =>
        val key = m.args.head
        val value = m.args.last

        // special cases for key type
        key.base match {
          case MDate =>
            refs.add("platform.Foundation.NSDate")
          case _ =>
        }

        // special cases for value type
        value.base match {
          case MDate =>
            refs.add("platform.Foundation.NSDate")
          case _ =>
        }

        // evaluate key and value types
        refs ++= typeRefs(key, requiresCast = true) ++ typeRefs(value, requiresCast = true)

      case MDate =>
        refs.add("kotlinx.datetime.toKotlinInstant")

      case e: MExtern if e.kotlin.isProtobufMessage =>
        refs.add(utils.withSupportPackage("toByteArray"))
        refs.add(utils.withCInteropPackage(objcMarshal.typename(m)))

      case d: MDef =>
        d.defType match {
          case DInterface =>
          // we don't support mapping of interfaces yet
          case DRecord =>
            // we need this when unboxing map values / optionals
            if(requiresCast) refs.add(utils.withCInteropPackage(objcMarshal.typename(m)))
          case _ =>
        }

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
        s"$valueName.map { " + map(s"${cast("it", listType)}", listType) + " }"
      case MSet =>
        s"$valueName.map { ${map(cast("it", tm.args.head), tm.args.head)} }.toSet()"

      case MMap =>
        val key = tm.args.head
        val value = tm.args.last

        // primitive key / value case
        s"$valueName.map { ${map(cast("it.key", key), key)} to ${map(cast("it.value", value), value)} }.toMap()"

      case d: MDef => d.body match {
        case _: Enum => s"${kotlinMarshal.typename(tm)}.fromObjc($valueName)"
        case _: Record => s"$valueName.toKotlin()"
        case i: Interface =>
          if (i.ext.cpp) {
            // a generated objc method return type for +c interfaces is optional
            s"$valueName?.let { ${kotlinMarshal.typename(tm)}Impl(it) }"
          } else {
            utils.throwUnsupported(s"Impossible to map ${objcMarshal.typename(tm)} in this direction")
          }
        case _ => utils.generateTodo(tm)
      }

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val kotlinName = kotlinMarshal.fqTypename(tm)
        s"$kotlinName.ADAPTER.decode($valueName.data()?.toByteArray() ?: ByteArray(0))"

      case e: MExtern =>
        utils.generateTodo(s"Map external type: ${e.kotlin.typename}")

      case MOptional =>
        val arg = tm.args.head
        arg.base match {
          case p: MPrimitive =>
            p._idlName match {
              case "bool" => s"$valueName?.boolValue()"
              case "i8" => s"$valueName?.charValue()"
              case "i16" => s"$valueName?.shortValue()"
              case "i32" => s"$valueName?.intValue()"
              case "i64" => s"$valueName?.longValue()"
              case "f32" => s"$valueName?.floatValue()"
              case "f64" => s"$valueName?.doubleValue()"
              case _ => utils.generateTodo("Map boxed primitive type: " + p._idlName)
            }
          case MString => map(s"$valueName", arg)
          case d: MDef => d.body match {
            case _: Enum => s"$valueName?.let { ${kotlinMarshal.typename(arg)}.fromNSNumber(it) }"
            case _: Record => map(s"$valueName?", arg)
            case i: Interface =>
              if(i.ext.cpp) {
                s"$valueName?.let { ${kotlinMarshal.typename(arg)}Impl(it) }"
              } else {
                utils.throwUnsupported(s"Impossible to map ${objcMarshal.typename(arg)} in this direction")
              }
            case _ => utils.generateTodo(tm)
          }

          case MSet =>
            val item = arg.args.head
            s"$valueName?.map { ${map(cast("it", item), item)} }?.toSet()"

          case MMap =>
            val key = arg.args.head
            val value = arg.args.last
            // primitive key / value case
            s"$valueName?.map { ${map(cast("it.key", key), key)} to ${map(cast("it.value", value), value)} }?.toMap()"

          case _ => map(s"$valueName?", arg)
        }

      case _ => utils.generateTodo(tm)
    }
  }

  private def cast(valueName: String, tm: MExpr): String = {
    val castType = tm.base match {
      case MOptional => s"${objcMarshal.typename(tm)}?"
      case MDate => "NSDate"
      case d: MDef =>
        d.defType match {
          case DEnum => "Long"
          case _ => objcMarshal.typename(tm)
        }
      case _: MExtern => objcMarshal.typename(tm)
      case MSet => "Set<*>"
      case _ => kotlinMarshal.typename(tm)
    }

    tm.base match {
      case MDate | _: MDef | _: MExtern | MSet | MOptional =>
        s"($valueName as $castType)"
      case _ => s"$valueName as $castType"
    }
  }
}
