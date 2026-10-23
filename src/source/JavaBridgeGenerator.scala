package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._
import djinni.writer.IndentWriter

import scala.collection.mutable

// Checks the bridge before any generator writes a file: a record that holds a +c interface has no converter,
// and an extern type whose two classes differ must be a protobuf message.
object JavaBridgeCheck {

  // A record without a converter. `detail` completes "bridge: skipped <record>: field <field> ...".
  case class Skip(record: String, field: String, detail: String)

  def skips(idl: Seq[TypeDecl]): Seq[Skip] = {
    val records = idl.collect { case d: InternTypeDecl if d.body.isInstanceOf[Record] => d }
    val skipped = mutable.LinkedHashMap[String, Skip]()
    var changed = true
    while (changed) {
      changed = false
      for (d <- records if !skipped.contains(d.ident.name)) {
        val fields = d.body.asInstanceOf[Record].fields
        fields.find(f => hasCppInterface(f.ty.resolved)) match {
          case Some(f) =>
            skipped(d.ident.name) = Skip(d.ident.name, f.ident.name, "is a +c interface")
            changed = true
          case None =>
            fields.flatMap(f => referencedRecords(f.ty.resolved).find(skipped.contains).map(name => (f, name))).headOption.foreach {
              case (f, name) =>
                skipped(d.ident.name) = Skip(d.ident.name, f.ident.name, s"holds $name, which is skipped")
                changed = true
            }
        }
      }
    }
    records.flatMap(d => skipped.get(d.ident.name))
  }

  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val skipped = skips(idl).map(_.record).toSet
    val problems = mutable.ArrayBuffer[String]()
    for (d <- idl.collect { case itd: InternTypeDecl => itd }) {
      d.body match {
        case r: Record if !skipped.contains(d.ident.name) =>
          if (r.ext.java) {
            problems += s"record ${d.ident.name}: a +j record is extended by application code, so the bridge cannot construct it."
          }
          if (d.params.nonEmpty) {
            problems += s"record ${d.ident.name}: a record with type parameters is not converted."
          }
          r.fields.foreach(f => problems ++= typeProblems(f.ty.resolved, s"record ${d.ident.name}, field ${f.ident.name}"))
        case i: Interface if i.ext.java =>
          if (d.params.nonEmpty) {
            problems += s"interface ${d.ident.name}: an interface with type parameters is not converted."
          }
          i.methods.filter(m => !m.static && m.lang.java).foreach { m =>
            m.params.foreach(p => problems ++= typeProblems(p.ty.resolved, s"interface ${d.ident.name}, method ${m.ident.name}, parameter ${p.ident.name}"))
            m.ret.foreach(r => problems ++= typeProblems(r.resolved, s"interface ${d.ident.name}, method ${m.ident.name}, return"))
          }
        case _ =>
      }
    }
    if (problems.isEmpty) None else Some(problems.mkString("\n"))
  }

  private def typeProblems(tm: MExpr, where: String): Seq[String] = tm.base match {
    case MOptional | MList | MSet | MArray => typeProblems(tm.args.head, where)
    case MMap => typeProblems(tm.args(0), where) ++ typeProblems(tm.args(1), where)
    case d: MDef => d.body match {
      case i: Interface if i.ext.cpp => Seq(s"$where: a +c interface is not converted. The adapter owns it.")
      case _ => Seq()
    }
    case e: MExtern =>
      val kotlinName = JavaBridgeGenerator.externKotlinName(e)
      if (kotlinName != JavaBridgeGenerator.externJavaName(e) && !e.kotlin.isProtobufMessage && e.name != "future" && e.name != "outcome") {
        Seq(s"$where: extern type ${e.name} is $kotlinName in Kotlin, not ${e.java.typename}, and the yaml does not mark it as a protobuf message. " +
          "Use the same class in both legs, or set kotlin.isProtobufMessage.")
      } else {
        tm.args.flatMap(a => typeProblems(a, where))
      }
    case _ => Seq()
  }

  private def hasCppInterface(tm: MExpr): Boolean = tm.base match {
    case d: MDef => d.body match {
      case i: Interface if i.ext.cpp => true
      case _ => tm.args.exists(hasCppInterface)
    }
    case _ => tm.args.exists(hasCppInterface)
  }

  private def referencedRecords(tm: MExpr): Seq[String] = tm.base match {
    case d: MDef if d.body.isInstanceOf[Record] => Seq(d.name) ++ tm.args.flatMap(referencedRecords)
    case _ => tm.args.flatMap(referencedRecords)
  }
}

// Writes Kotlin extension functions and wrappers that convert between the Java classes of one generator run and
// the Kotlin JNI classes of another run.
class JavaBridgeGenerator(spec: Spec) extends Generator(spec) {

  private val kotlinMarshal = new KotlinJniMarshal(spec)
  private val javaMarshal = new JavaMarshal(spec.copy(javaPackage = spec.kotlinJniJavaBridgePackage))
  private val kt = KotlinJniIdent.escape _

  private val packageName: String =
    spec.kotlinJniPackage.orElse(spec.javaPackage).fold("javabridge")(_ + ".javabridge")

  private var skipped: Set[String] = Set()

  private def javaType(tm: MExpr): String = javaMarshal.fqTypename(tm)
  private def kotlinType(tm: MExpr): String = kotlinMarshal.fqTypename(tm)

  private val bridgePackage = spec.kotlinJniJavaBridgePackage.getOrElse("")
  private val kotlinPackage = spec.kotlinJniPackage.orElse(spec.javaPackage).getOrElse("")

  // A type of the Java side in Kotlin syntax. The Java class of the other run has Kotlin names for the primitives
  // and for byte[], and it keeps the Java class of an extern type.
  private def javaValueType(tm: MExpr): String = bridgeKotlinType(tm, bridgePackage, kotlinExterns = false)
  private def kotlinValueType(tm: MExpr): String = bridgeKotlinType(tm, kotlinPackage, kotlinExterns = true)

  private def isInterface(tm: MExpr): Boolean = tm.base match {
    case d: MDef => d.body.isInstanceOf[Interface]
    case e: MExtern => e.defType == DInterface
    case _ => false
  }

  private def bridgeKotlinType(tm: MExpr, packageName: String, kotlinExterns: Boolean): String = {
    def args(tm: MExpr): String = if (tm.args.isEmpty) "" else tm.args.map(a => f(a)).mkString("<", ", ", ">")
    def f(tm: MExpr): String = tm.base match {
      case MOptional => f(tm.args.head) + "?"
      case MArray =>
        tm.args.head.base match {
          case p: MPrimitive => p.kName + "Array"
          case _ => "Array<" + f(tm.args.head) + ">"
        }
      case e: MExtern =>
        val name = if (kotlinExterns) JavaBridgeGenerator.externKotlinName(e) else JavaBridgeGenerator.externJavaName(e)
        name + (if (e.java.generic) args(tm) else "")
      case p: MProtobuf => (if (p.body.java.pkg.isEmpty) "" else p.body.java.pkg + ".") + p.name
      case p: MPrimitive => p.kName
      case MString => "String"
      case MDate => "java.util.Date"
      case MBinary => "ByteArray"
      case MList => "ArrayList" + args(tm)
      case MSet => "HashSet" + args(tm)
      case MMap => "HashMap" + args(tm)
      case d: MDef => (if (packageName.isEmpty) "" else packageName + ".") + idJava.ty(d.name) + args(tm)
      case p: MParam => idJava.typeParam(p.name)
      case MVoid => "Void"
    }
    if (javaMarshal.isEnumFlags(tm)) {
      val inner = if (tm.base == MOptional) tm.args.head else tm
      "java.util.EnumSet<" + f(inner) + ">" + (if (tm.base == MOptional) "?" else "")
    } else {
      val name = f(tm)
      if (isInterface(tm) && !name.endsWith("?") && spec.cppNnType.isEmpty) name + "?" else name
    }
  }

  private def writeFile(name: String, origin: String)(f: IndentWriter => Unit) {
    createFile(spec.kotlinJniJavaBridgeOutFolder.get, name + ".kt", (w: IndentWriter) => {
      w.wl("// AUTOGENERATED FILE - DO NOT MODIFY!")
      w.wl("// This file was generated by Djinni from " + origin)
      w.wl
      w.wl(s"package $packageName")
      w.wl
      f(w)
    })
  }

  override def generate(idl: Seq[TypeDecl]) {
    val skips = JavaBridgeCheck.skips(idl)
    skipped = skips.map(_.record).toSet
    skips.foreach(s => println(s"bridge: skipped ${s.record}: field ${s.field} ${s.detail}"))
    super.generate(idl)
  }

  override def generateEnum(origin: String, ident: Ident, doc: Doc, e: Enum) {
    val javaName = javaMarshal.fqTypename(ident.name, e)
    val kotlinName = kotlinMarshal.fqTypename(ident.name, e)
    writeFile(idJava.ty(ident.name) + "Bridge", origin) { w =>
      writeEnumConversion(w, javaName, kotlinName, e, "toKotlinJni")
      w.wl
      writeEnumConversion(w, kotlinName, javaName, e, "toJava")
    }
  }

  private def writeEnumConversion(w: IndentWriter, from: String, to: String, e: Enum, name: String) {
    val options = normalEnumOptions(e)
    w.wl(s"fun $from.$name(): $to = when (this) {").nested {
      if (options.isEmpty) {
        w.wl("""else -> throw IllegalStateException("The enum has no options")""")
      } else {
        options.foreach(o => w.wl(s"$from.${idJava.enum(o.ident)} -> $to.${idJava.enum(o.ident)}"))
      }
    }
    w.wl("}")
  }

  override def generateRecord(origin: String, ident: Ident, doc: Doc, params: Seq[TypeParam], r: Record) {
    if (skipped.contains(ident.name)) {
      return
    }
    val javaName = javaMarshal.fqTypename(ident.name, r)
    val kotlinName = kotlinMarshal.fqTypename(ident.name, r)
    writeFile(idJava.ty(ident.name) + "Bridge", origin) { w =>
      writeRecordConversion(w, javaName, kotlinName, r, toKotlin = true)
      w.wl
      writeRecordConversion(w, kotlinName, javaName, r, toKotlin = false)
    }
  }

  private def writeRecordConversion(w: IndentWriter, from: String, to: String, r: Record, toKotlin: Boolean) {
    val name = if (toKotlin) "toKotlinJni" else "toJava"
    w.wl(s"fun $from.$name(): $to = $to(")
    w.nested {
      r.fields.zipWithIndex.foreach { case (f, index) =>
        val field = if (toKotlin) javaProperty(f) else kt(idJava.field(f.ident))
        val value = convert(f.ty.resolved, "this." + field, toKotlin)
        w.wl(value + (if (index < r.fields.size - 1) "," else ""))
      }
    }
    w.wl(")")
  }

  // The Java field name follows --ident-java-field, and the getter does not. Call the getter, so the bridge
  // reads a field that the Java class does not expose.
  private def javaProperty(f: Field): String = idJava.method("get_" + f.ident.name) + "()"

  override def generateInterface(origin: String, ident: Ident, doc: Doc, typeParams: Seq[TypeParam], i: Interface) {
    if (!i.ext.java) {
      return
    }
    val javaName = javaMarshal.fqTypename(ident.name, i)
    val kotlinName = kotlinMarshal.fqTypename(ident.name, i)
    val javaInterface = isJavaInterface(i)
    val kotlinInterface = isKotlinInterface(i)
    writeFile(idJava.ty(ident.name) + "JavaBridge", origin) { w =>
      writeBridgeClass(w, ident, i, javaName, kotlinName, javaInterface, toJavaSide = true)
      w.wl
      writeBridgeClass(w, ident, i, kotlinName, javaName, kotlinInterface, toJavaSide = false)
      w.wl
      w.wl(s"fun $javaName.toKotlinJni(): $kotlinName = ${idJava.ty(ident.name)}KotlinBridge(this)")
      w.wl
      w.wl(s"fun $kotlinName.toJava(): $javaName = ${idJava.ty(ident.name)}JavaBridge(this)")
    }
  }

  private def isJavaInterface(i: Interface): Boolean =
    spec.javaGenInterface && !i.ext.cpp && !i.methods.exists(m => m.static && m.lang.java)

  private def isKotlinInterface(i: Interface): Boolean = isJavaInterface(i)

  private def writeBridgeClass(w: IndentWriter, ident: Ident, i: Interface, implementsName: String, implName: String,
                               implementsIsInterface: Boolean, toJavaSide: Boolean) {
    val simple = idJava.ty(ident.name) + (if (toJavaSide) "JavaBridge" else "KotlinBridge")
    val superCall = if (implementsIsInterface) implementsName else implementsName + "()"
    w.wl(s"class $simple(private val impl: $implName) : $superCall {").nested {
      val methods = i.methods.filter(m => !m.static && m.lang.java)
      methods.zipWithIndex.foreach { case (m, index) =>
        if (index > 0) {
          w.wl
        }
        writeBridgeMethod(w, m, toJavaSide)
      }
    }
    w.wl("}")
  }

  private def methodName(m: Interface.Method): String = kt(idJava.method(m.ident))

  private def writeBridgeMethod(w: IndentWriter, m: Interface.Method, toJavaSide: Boolean) {
    val params = m.params.map { p =>
      val ty = if (toJavaSide) javaValueType(p.ty.resolved) else kotlinValueType(p.ty.resolved)
      s"${kt(idJava.local(p.ident))}: $ty"
    }.mkString(", ")
    val ret = m.ret.map(r => if (toJavaSide) javaValueType(r.resolved) else kotlinValueType(r.resolved))
    val signature = ret.fold(s"override fun ${methodName(m)}($params)") { t => s"override fun ${methodName(m)}($params): $t" }
    w.w(signature).braced {
      val args = m.params.map(p => convertArgument(p.ty.resolved, kt(idJava.local(p.ident)), toJavaSide))
      val call = s"this.impl.${methodName(m)}(${args.mkString(", ")})"
      m.ret match {
        case None =>
          w.wl(call)
        case Some(r) =>
          w.wl("return " + convertReturn(r.resolved, call, toJavaSide))
      }
    }
  }

  // A method argument of the Java side is a Java value that the Kotlin implementation needs, and the other way.
  private def convertArgument(tm: MExpr, expr: String, toJavaSide: Boolean): String = {
    val toKotlin = toJavaSide
    futureArg(tm) match {
      case Some(inner) =>
        if (!needsConversion(inner)) {
          expr
        } else {
          val (from, to) = if (toKotlin) (javaValueType(inner), kotlinValueType(inner)) else (kotlinValueType(inner), javaValueType(inner))
          s"$expr.then(${futureClass(tm)}.FutureHandlerWithReturn<$from, $to> { djinni_future -> ${convertValue(inner, "djinni_future.get()", toKotlin)} })"
        }
      case None =>
        outcomeArgs(tm) match {
          case Some((value, error)) =>
            if (!needsConversion(value) && !needsConversion(error)) {
              expr
            } else {
              convertOutcome(expr, tm, value, error, toKotlin)
            }
          case None => convert(tm, expr, toKotlin)
        }
    }
  }

  private def convertReturn(tm: MExpr, call: String, toJavaSide: Boolean): String = {
    val toKotlin = !toJavaSide
    futureArg(tm) match {
      case Some(inner) =>
        if (!needsConversion(inner)) {
          call
        } else {
          val (from, to) = if (toKotlin) (javaValueType(inner), kotlinValueType(inner)) else (kotlinValueType(inner), javaValueType(inner))
          s"$call.then(${futureClass(tm)}.FutureHandlerWithReturn<$from, $to> { djinni_future -> ${convertValue(inner, "djinni_future.get()", toKotlin)} })"
        }
      case None =>
        outcomeArgs(tm) match {
          case Some((value, error)) =>
            if (!needsConversion(value) && !needsConversion(error)) {
              call
            } else {
              convertOutcome(call, tm, value, error, toKotlin)
            }
          case None => convert(tm, call, toKotlin)
        }
    }
  }

  // Builds the outcome of the other leg. The handlers get the value or the error of the source leg.
  private def convertOutcome(expr: String, tm: MExpr, value: MExpr, error: MExpr, toKotlin: Boolean): String = {
    val outcomeClass = tm.base.asInstanceOf[MExtern].java.typename
    val targetOutcome = if (toKotlin) kotlinValueType(tm) else javaValueType(tm)
    val sourceValue = if (toKotlin) javaValueType(value) else kotlinValueType(value)
    val sourceError = if (toKotlin) javaValueType(error) else kotlinValueType(error)
    val targetValue = if (toKotlin) kotlinValueType(value) else javaValueType(value)
    val targetError = if (toKotlin) kotlinValueType(error) else javaValueType(error)
    val result = if (value.base == MVoid) {
      s"$outcomeClass.fromResult<$targetValue, $targetError>(null)"
    } else {
      s"$outcomeClass.fromResult<$targetValue, $targetError>(${convert(value, "djinni_value", toKotlin)})"
    }
    val failure = s"$outcomeClass.fromError<$targetValue, $targetError>(${convert(error, "djinni_error", toKotlin)})"
    s"$expr.match(" +
      s"$outcomeClass.ResultHandler<$targetOutcome, $sourceValue> { djinni_value -> $result }, " +
      s"$outcomeClass.ErrorHandler<$targetOutcome, $sourceError> { djinni_error -> $failure })"
  }

  // A value of the other leg, also when it is an outcome inside a future.
  private def convertValue(tm: MExpr, expr: String, toKotlin: Boolean): String = {
    outcomeArgs(tm) match {
      case Some((value, error)) =>
        if (needsConversion(value) || needsConversion(error)) {
          convertOutcome(expr, tm, value, error, toKotlin)
        } else {
          expr
        }
      case None => convert(tm, expr, toKotlin)
    }
  }

  private def futureArg(tm: MExpr): Option[MExpr] = tm.base match {
    case e: MExtern if e.name == "future" && tm.args.size == 1 => Some(tm.args.head)
    case _ => None
  }

  private def outcomeArgs(tm: MExpr): Option[(MExpr, MExpr)] = tm.base match {
    case e: MExtern if e.name == "outcome" && tm.args.size == 2 => Some((tm.args(0), tm.args(1)))
    case _ => None
  }

  private def futureClass(tm: MExpr): String = tm.base.asInstanceOf[MExtern].java.typename

  private def needsConversion(tm: MExpr): Boolean = tm.base match {
    case MOptional | MList | MSet | MArray => needsConversion(tm.args.head)
    case MMap => tm.args.exists(needsConversion)
    case d: MDef => d.body match {
      case e: Enum if e.flags => true
      case _: Record | _: Enum | _: Interface => true
      case _ => false
    }
    case e: MExtern =>
      if (e.name == "future" || e.name == "outcome") {
        tm.args.exists(needsConversion)
      } else {
        JavaBridgeGenerator.externKotlinName(e) != JavaBridgeGenerator.externJavaName(e)
      }
    case _ => false
  }

  private def convert(tm: MExpr, expr: String, toKotlin: Boolean): String = {
    val name = if (toKotlin) "toKotlinJni" else "toJava"
    tm.base match {
      case MOptional =>
        val inner = tm.args.head
        if (needsConversion(inner)) {
          s"$expr?.let { djinni_value -> ${convert(inner, "djinni_value", toKotlin)} }"
        } else {
          expr
        }
      case MList =>
        val inner = tm.args.head
        if (needsConversion(inner)) {
          s"ArrayList($expr.map { djinni_item -> ${convert(inner, "djinni_item", toKotlin)} })"
        } else {
          expr
        }
      case MSet =>
        val inner = tm.args.head
        if (needsConversion(inner)) {
          s"HashSet($expr.map { djinni_item -> ${convert(inner, "djinni_item", toKotlin)} })"
        } else {
          expr
        }
      case MMap =>
        val key = tm.args(0)
        val value = tm.args(1)
        if (needsConversion(key) || needsConversion(value)) {
          s"HashMap($expr.map { djinni_entry -> ${convert(key, "djinni_entry.key", toKotlin)} to ${convert(value, "djinni_entry.value", toKotlin)} }.toMap())"
        } else {
          expr
        }
      case MArray =>
        val inner = tm.args.head
        if (needsConversion(inner)) {
          s"$expr.map { djinni_item -> ${convert(inner, "djinni_item", toKotlin)} }.toTypedArray()"
        } else {
          expr
        }
      case d: MDef =>
        d.body match {
          case e: Enum if e.flags =>
            val target = if (toKotlin) kotlinMarshal.fqTypename(d.name, e) else javaMarshal.fqTypename(d.name, e)
            val method = if (toKotlin) "toKotlinJni" else "toJava"
            s"$expr.let { djinni_flags -> java.util.EnumSet.noneOf($target::class.java).apply { djinni_flags.forEach { djinni_option -> add(djinni_option.$method()) } } }"
          case _: Record | _: Enum =>
            s"$expr.$name()"
          case _: Interface =>
            if (spec.cppNnType.isEmpty) s"$expr?.$name()" else s"$expr.$name()"
          case _ =>
            expr
        }
      case e: MExtern =>
        if (e.name == "future" || e.name == "outcome") {
          throw GenerateException(s"extern type ${e.name} is only converted as a method parameter or return.")
        } else if (!needsConversion(tm)) {
          expr
        } else if (e.kotlin.isProtobufMessage) {
          val target = if (toKotlin) JavaBridgeGenerator.externKotlinName(e) else e.java.typename
          s"$target.parseFrom($expr.toByteArray())"
        } else {
          throw GenerateException(s"extern type ${e.name} has no converter between ${e.java.typename} and ${JavaBridgeGenerator.externKotlinName(e)}.")
        }
      case _ =>
        expr
    }
  }
}

object JavaBridgeGenerator {
  private val javaToKotlin = Map(
    "boolean" -> "Boolean", "byte" -> "Byte", "short" -> "Short", "int" -> "Int", "long" -> "Long",
    "float" -> "Float", "double" -> "Double", "void" -> "Unit",
    "java.lang.Boolean" -> "Boolean", "java.lang.Byte" -> "Byte", "java.lang.Short" -> "Short",
    "java.lang.Integer" -> "Int", "java.lang.Long" -> "Long", "java.lang.Float" -> "Float",
    "java.lang.Double" -> "Double", "java.lang.String" -> "String", "java.lang.Object" -> "Any")

  def externJavaName(e: MExtern): String = javaToKotlin.getOrElse(e.java.typename, e.java.typename)

  def externKotlinName(e: MExtern): String = e.kotlin.jniTypename.getOrElse(externJavaName(e))
}
