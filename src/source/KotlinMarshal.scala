package djinni

import generatorTools.{ImportRef, Spec, SymbolReference}

import ast.TypeRef
import meta.{MDate, MDef, MExpr, MExtern, MList, MMap, MOpaque, MOptional, MPrimitive, MSet, MString, Meta}

class KotlinMarshal(spec: Spec) extends Marshal(spec) {

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
        case _ => List()
      }
    case _ => List()
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
            case d: MDef => if (fullyQualified) withPackage(spec.kotlinPackage, idKotlin.ty(d.name)) else idKotlin.ty(d.name)
            case _ => ""
          }
          base + args(tm)
      }
    }
    f(tm)
  }

  private def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)
}
