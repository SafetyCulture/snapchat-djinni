package djinni

import generatorTools.{ImportRef, Spec, SymbolReference}
import ast.{Interface, TypeRef}
import meta.{DEnum, DInterface, DRecord, MBinary, MDate, MDef, MExpr, MExtern, MList, MMap, MOpaque, MOptional, MPrimitive, MSet, MString, Meta}

class KotlinMarshal(spec: Spec) extends Marshal(spec) {
  private val utils = new KMPUtils(this, spec)

  override def typename(tm: meta.MExpr): String = toKotlinType(tm)
  override def fqTypename(tm: meta.MExpr): String = toKotlinType(tm, fullyQualified = true)

  override def paramType(tm: meta.MExpr): String = toKotlinType(tm)
  override def fqParamType(tm: meta.MExpr): String = toKotlinType(tm, fullyQualified = true)

  override def returnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => toKotlinType(ty.resolved))
  override def fqReturnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => toKotlinType(ty.resolved, fullyQualified = true))

  override def fieldType(tm: meta.MExpr): String = toKotlinType(tm)
  override def fqFieldType(tm: meta.MExpr): String = toKotlinType(tm, fullyQualified = true)

  /* here we can define any imports required for specific Meta */
  def references(m: Meta): Seq[SymbolReference] = m match {
    case o: MOpaque =>
      o match {
        case MDate => List(ImportRef("kotlinx.datetime.Instant"))
        case MBinary => List(ImportRef("kotlinx.io.Buffer"))
        case _ => List()
      }
    case _ => List()
  }

  def cinteropReturnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => cinteropType(ty.resolved))
  def cinteropType(tm: meta.MExpr, fullyQualified: Boolean = false): String = {
    tm.base match {
      case d: MDef => d.defType match {
        case DRecord | DEnum => idObjc.ty(d.name)
        case DInterface => idObjc.ty(d.name) + "Protocol"
      }
      case e: MExtern => e.objc.typename
      case MList => "List<*>"
      case MMap => "Map<Any?, *>"
      case MDate => "NSDate"
      case MOptional => cinteropType(tm.args.head, fullyQualified) + "?"
      case _ => toKotlinType(tm, fullyQualified)
    }
  }

  def javaInteropReturnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => javaInteropType(ty.resolved))
  def javaInteropType(tm: meta.MExpr): String = {
    def args(tm: MExpr) = if (tm.args.isEmpty) "" else tm.args.map(f).mkString("<", ", ", ">")
    def f(tm: MExpr): String = {
      tm.base match {
        case d: MDef => utils.withPackage(spec.javaPackage, idJava.ty(d.name))
        case e: MExtern => e.java.typename + (if(e.java.generic) args(tm) else "")
        case MList => "ArrayList" + args(tm)
        case MMap => "HashMap" + args(tm)
        case MDate => "Date"
        case MOptional => javaInteropType(tm.args.head) + "?"
        case _ => toKotlinType(tm)
      }
    }
    f(tm)
  }

  def synthesisedJavaProperty(m: Interface.Method): Option[String] = {

    def kotlinDecapitalize(name: String): String = {
      if (name.isEmpty) return name

      // Count consecutive uppercase letters from the start
      val upperCount = name.takeWhile(_.isUpper).length

      upperCount match {
        case 0 => name // No uppercase letters at start
        case 1 => name.head.toLower + name.tail // Single uppercase letter
        case n if n == name.length => name.toLowerCase // All uppercase
        case n =>
          // Multiple uppercase letters: lowercase all but the last uppercase
          // e.g. "UIService" -> "uiService", "HTTPClient" -> "httpClient"
          name.take(n - 1).toLowerCase + name.drop(n - 1)
      }
    }

    m.ret.flatMap(r =>
      if (m.params.nonEmpty) None
      else idJava.method(m.ident.name) match {
        case n if n.startsWith("get") =>
          val propertyPart = n.substring(3)
          if (propertyPart.nonEmpty) Some(kotlinDecapitalize(propertyPart))
          else None
        case n if n.startsWith("is") =>
          r.resolved.base match {
            case p: MPrimitive if p._idlName == "bool" => Some(n)
            case _ => None
          }
        case _ => None
      }
    )
  }

  /* generate a kotlin type for the given MExpr */
  def toKotlinType(tm: meta.MExpr, fullyQualified: Boolean = false): String = {
    def args(tm: MExpr) = if (tm.args.isEmpty) "" else tm.args.map(f).mkString("<", ", ", ">")
    def f(tm: MExpr): String = {
      tm.base match {
        case MOptional =>
          assert(tm.args.size == 1)
          val arg = tm.args.head
          arg.base match {
            case m => f(arg) + "?"
          }
        case e: MExtern => e.kotlin.typename
        case o =>
          val base = o match {
            case p: MPrimitive => p.kName
            case MString => "String"
            case MDate => "Instant"
            case MList => "List"
            case MSet => "Set"
            case MMap => "Map"
            case d: MDef => if (fullyQualified) utils.withPackage(spec.kotlinPackage, idKotlin.ty(d.name)) else idKotlin.ty(d.name)
            case MBinary => "Buffer"
            case _ => utils.generateTodo(tm)
          }
          base + args(tm)
      }
    }
    f(tm)
  }
}
