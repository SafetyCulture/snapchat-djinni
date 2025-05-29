package djinni

import meta._

import djinni.generatorTools.Spec

import scala.collection.mutable

class KMPIOSKotlinMapper(marshal: KotlinMarshal, objcMarshal: ObjcMarshal, spec: Spec) {

  def typeRefs(m: MExpr): Set[String] = {
    val refs = mutable.Set[String]()
    m.base match {
      case MOptional =>
        // evaluate optional type
        refs ++= typeRefs(m.args.head)

      case MList | MSet =>
        // special cases for list / set types
        m.args.head.base match {
          case MDate =>
            // will need to cast the list / set type to NSDate
            refs.add("platform.Foundation.NSDate")
          case _ =>
        }

        // evaluate list / set type
        refs ++= typeRefs(m.args.head)

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
        refs ++= typeRefs(key) ++ typeRefs(value)

      case MDate =>
        refs.add("kotlinx.datetime.toKotlinInstant")

      case e: MExtern if e.kotlin.isProtobufMessage =>
        refs.add(withSupportPackage("toByteArray"))
        refs.add(withPackage(Some(e.kotlin.pkg), marshal.typename(m)))
        refs.add(withCInteropPackage(objcMarshal.typename(m)))

      case d: MDef =>
        d.defType match {
          case DInterface =>
          // we don't support mapping of interfaces yet
          case DRecord =>
            // we need this when unboxing map values / optionals
            refs.add(withCInteropPackage(objcMarshal.typename(m)))
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

      case d: MDef => d.defType match {
        case DEnum => s"${marshal.typename(tm)}.fromObjc($valueName)"
        case DRecord => s"$valueName.toKotlin()"
        case DInterface => generateTodo(d)
      }

      case e: MExtern if e.kotlin.isProtobufMessage =>
        val kotlinName = e.kotlin.typename
        s"$kotlinName.ADAPTER.decode($valueName.data()?.toByteArray() ?: ByteArray(0))"

      case e: MExtern =>
        generateTodo(s"Map external type: ${e.kotlin.typename}")

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
              case _ => generateTodo("Map boxed primitive type: " + p._idlName)
            }
          case MString => map(s"$valueName", arg)
          case d: MDef if d.defType == DEnum => s"$valueName?.let { ${marshal.typename(arg)}.fromNSNumber(it) }"

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

      case _ => generateTodo(tm.base)
    }
  }

  def cast(valueName: String, tm: MExpr): String = {
    val castType = tm.base match {
      case MDate => "NSDate"
      case d: MDef =>
        d.defType match {
          case DEnum => "Long"
          case _ => objcMarshal.typename(tm)
        }
      case _: MExtern => objcMarshal.typename(tm)
      case _ => marshal.typename(tm)
    }

    tm.base match {
      case MDate | _: MDef | _: MExtern =>
        s"($valueName as $castType)"
      case _ => s"$valueName as $castType"
    }
  }

  def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)

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
