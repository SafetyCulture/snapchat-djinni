package djinni

import generatorTools.{ImportRef, Spec, SymbolReference}

import djinni.ast.TypeRef
import djinni.meta.{MDate, MDef, MExpr, MExtern, MList, MMap, MOpaque, MPrimitive, MSet, MString, Meta}

class KotlinMarshal(spec: Spec) extends Marshal(spec) {

  override def typename(tm: meta.MExpr): String = toKotlinType(tm, None)
  override def fqTypename(tm: meta.MExpr): String = toKotlinType(tm, spec.kotlinPackage)

  override def paramType(tm: meta.MExpr): String = toKotlinType(tm, None)
  override def fqParamType(tm: meta.MExpr): String = toKotlinType(tm, spec.kotlinPackage)

  override def returnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => toKotlinType(ty.resolved, None))
  override def fqReturnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => toKotlinType(ty.resolved, spec.kotlinPackage))

  override def fieldType(tm: meta.MExpr): String = toKotlinType(tm, None)
  override def fqFieldType(tm: meta.MExpr): String = toKotlinType(tm, spec.kotlinPackage)

  /* here we can define any imports required for specific Meta */
  def references(m: Meta): Seq[SymbolReference] = m match {
    case o: MOpaque =>
      o match {
        case MDate => List(ImportRef("kotlinx.datetime.LocalDate"))
        case _ => List()
      }
    case e: MExtern => List(ImportRef(withPackage(Some(e.kotlin.pkg), e.kotlin.typename)))
    case _ => List()
  }

  /* generate a kotlin type for the given MExpr */
  def toKotlinType(tm: meta.MExpr, packageName: Option[String]): String = {
    def args(tm: MExpr) = if (tm.args.isEmpty) "" else tm.args.map(f(_, true)).mkString("<", ", ", ">")
    def f(tm: MExpr, needRef: Boolean): String = {
      tm.base match {
        case p: MExtern => p.kotlin.typename
        case o =>
          val base = o match {
            case p: MPrimitive => p.kName
            case MString => "String"
            case MDate => "LocalDate"
            case MList => "List"
            case MSet => "Set"
            case MMap => "Map"
            case d: MDef => withPackage(packageName, idKotlin.ty(d.name))
            case _ => ""
          }
          base + args(tm)
      }
    }
    f(tm, false)
  }

  private def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)
}
