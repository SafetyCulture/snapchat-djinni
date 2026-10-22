package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

object KotlinJniIdent {
  // Kotlin hard keywords. A name that is one of them needs backticks. The JVM name does not change.
  val keywords = Set(
    "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "null",
    "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof", "val", "var",
    "when", "while")

  def escape(ident: String): String = if (keywords.contains(ident)) "`" + ident + "`" else ident
}

// Kotlin types for the classes that the JNI code of JNIGenerator binds. The JVM signatures equal the Java ones.
class KotlinJniMarshal(spec: Spec) extends Marshal(spec) {
  private val javaMarshal = new JavaMarshal(spec)

  val packageName: Option[String] = spec.kotlinJniPackage.orElse(spec.javaPackage)

  // An interface reference is nullable only when the Java code marks it so.
  private val interfaceNullable = spec.cppNnType.isEmpty && spec.javaNullableAnnotation.isDefined

  override def typename(tm: MExpr): String = toKotlinType(tm, None)
  def typename(name: String, ty: TypeDef): String = idJava.ty(name)

  override def fqTypename(tm: MExpr): String = toKotlinType(tm, packageName)
  def fqTypename(name: String, ty: TypeDef): String = withPackage(packageName, idJava.ty(name))

  override def paramType(tm: MExpr): String = valueType(tm, None)
  override def fqParamType(tm: MExpr): String = valueType(tm, packageName)

  override def returnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => valueType(ty.resolved, None))
  override def fqReturnType(ret: Option[TypeRef]): String = ret.fold("Unit")(ty => valueType(ty.resolved, packageName))

  override def fieldType(tm: MExpr): String = valueType(tm, None)
  override def fqFieldType(tm: MExpr): String = valueType(tm, packageName)

  override def toCpp(tm: MExpr, expr: String): String = throw new AssertionError("direct kotlin to cpp conversion not possible")
  override def fromCpp(tm: MExpr, expr: String): String = throw new AssertionError("direct cpp to kotlin conversion not possible")

  def references(m: Meta): Seq[SymbolReference] = m match {
    case MDate => List(ImportRef("java.util.Date"))
    case p: MProtobuf => List(ImportRef(withPackage(Some(p.body.java.pkg), p.name)))
    case e if javaMarshal.isEnumFlags(e) => List(ImportRef("java.util.EnumSet"))
    case _ => List()
  }

  private def isInterface(tm: MExpr): Boolean = tm.base match {
    case d: MDef => d.defType == DInterface
    case e: MExtern => e.defType == DInterface
    case _ => false
  }

  private def valueType(tm: MExpr, pkg: Option[String]): String = {
    val name = toKotlinType(tm, pkg)
    val withFlags = if (javaMarshal.isEnumFlags(tm)) s"EnumSet<${stripNullable(name)}>" else name
    if (!withFlags.endsWith("?") && interfaceNullable && isInterface(tm)) withFlags + "?" else withFlags
  }

  private def stripNullable(t: String) = t.stripSuffix("?")

  private val javaToKotlin = Map(
    "boolean" -> "Boolean", "byte" -> "Byte", "short" -> "Short", "int" -> "Int", "long" -> "Long",
    "float" -> "Float", "double" -> "Double", "void" -> "Unit",
    "java.lang.Boolean" -> "Boolean", "java.lang.Byte" -> "Byte", "java.lang.Short" -> "Short",
    "java.lang.Integer" -> "Int", "java.lang.Long" -> "Long", "java.lang.Float" -> "Float",
    "java.lang.Double" -> "Double", "java.lang.String" -> "String", "java.lang.Object" -> "Any")

  private def externName(name: String) = javaToKotlin.getOrElse(name, name)

  private def toKotlinType(tm: MExpr, pkg: Option[String]): String = {
    def args(tm: MExpr) = if (tm.args.isEmpty) "" else tm.args.map(f(_, true)).mkString("<", ", ", ">")
    def f(tm: MExpr, needRef: Boolean): String = {
      tm.base match {
        case MOptional =>
          assert(tm.args.size == 1)
          val arg = tm.args.head
          arg.base match {
            case MOptional => throw new AssertionError("nested optional?")
            case _ => f(arg, true) + "?"
          }
        case MArray =>
          val elem = tm.args.head
          elem.base match {
            case p: MPrimitive => p.kName + "Array"
            case _ => "Array<" + f(elem, true) + ">"
          }
        case e: MExtern =>
          val boxed = externName(if (needRef) e.java.boxed else e.java.typename)
          boxed + (if (e.java.generic) args(tm) else "")
        case p: MProtobuf => p.name
        case o =>
          val base = o match {
            case p: MPrimitive => p.kName
            case MString => "String"
            case MDate => "Date"
            case MBinary => "ByteArray"
            case MList => "ArrayList"
            case MSet => "HashSet"
            case MMap => "HashMap"
            case d: MDef => withPackage(pkg, idJava.ty(d.name))
            case p: MParam => idJava.typeParam(p.name)
            case MVoid => "Void"
            case _ => throw new AssertionError("unreachable")
          }
          base + args(tm)
      }
    }
    f(tm, false)
  }

  private def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)
}
