/**
  * Copyright 2024 Snap, Inc.
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *    http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  */

package djinni

import djinni.ast._
import djinni.generatorTools._
import djinni.meta._

object SwiftIdent {
  // Swift cannot escape these with backticks in member or type position, so they get a trailing underscore.
  val unescapable = Set("Any", "Type", "Protocol", "self", "Self", "init", "deinit", "subscript")

  val keywords = Set(
    "associatedtype", "class", "enum", "extension", "fileprivate", "func", "import", "inout", "internal", "let",
    "open", "operator", "private", "precedencegroup", "protocol", "public", "rethrows", "static", "struct",
    "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while", "as", "await", "false",
    "is", "nil", "super", "throws", "true", "try")

  def escape(ident: String): String =
    if (unescapable.contains(ident)) ident + "_"
    else if (keywords.contains(ident)) "`" + ident + "`"
    else ident

  // An argument label at a call site does not need backticks, except for inout.
  def label(ident: String): String = if (ident == "`inout`") ident else ident.replace("`", "")

  // The name without escaping, for identifiers that are part of a longer name.
  def plain(ident: String): String = IdentStyle.camelLower(ident)

  // Names that the generated marshaller of a record uses: the closure parameter and the C++ namespace.
  val reservedLocals = Set("p", "djinni")

  // A local name that differs from every name in `taken`. The base name stays when it is free, so the output
  // of an IDL without the collision does not change.
  def fresh(base: String, taken: Set[String]): String = {
    var name = base
    while (taken.contains(name)) name += "_"
    name
  }
}

// The imports and the doc names of --swift-cxx-free-api. DjinniSupportCore owns the future type, and the C++ layer
// stays in DjinniSupport.
object SwiftSupport {
  // The module of the one DjinniSupport type that a public declaration names.
  def publicModule(enabled: Boolean, module: String, typename: String): String =
    if (enabled && module == "DjinniSupport" && typename == "DJFuture") "DjinniSupportCore" else module

  // The module of djinniCallQueue, which only the doc comment of an async wrapper names.
  def callQueueModule(enabled: Boolean): String = if (enabled) "DjinniSupportCore" else "DjinniSupport"
}

class SwiftMarshal(spec: Spec) extends Marshal(spec) {
  override def typename(tm: MExpr): String = toSwiftType(tm, None)
  def typename(name: String, ty: TypeDef): String = idSwift.ty(name)

  override def fqTypename(tm: MExpr): String = toSwiftType(tm, Some(spec.swiftModule))
  def fqTypename(name: String, ty: TypeDef): String = withPackage(Some(spec.swiftModule), idSwift.ty(name))

  override def paramType(tm: MExpr): String = toSwiftType(tm, None)
  override def fqParamType(tm: MExpr): String = toSwiftType(tm, Some(spec.swiftModule))

  override def returnType(ret: Option[TypeRef]): String = ret.fold("Void")(ty => toSwiftType(ty.resolved, None))
  override def fqReturnType(ret: Option[TypeRef]): String = ret.fold("Void")(ty => toSwiftType(ty.resolved, Some(spec.swiftModule)))

  override def fieldType(tm: MExpr): String = toSwiftType(tm, None)
  override def fqFieldType(tm: MExpr): String = toSwiftType(tm, Some(spec.swiftModule))

  override def toCpp(tm: MExpr, expr: String): String = s"${helperClass(tm)}.toCpp(${expr})"
  override def fromCpp(tm: MExpr, expr: String): String = s"${helperClass(tm)}.fromCpp(${expr})"

  def isOutcome(tm: MExpr): Boolean = tm.base match {
    case e: MExtern => e.name == "outcome" && tm.args.size == 2
    case _ => false
  }

  // True when the type is a record with the Swift name of the error record.
  def isErrorRecord(tm: MExpr, name: String): Boolean = tm.base match {
    case d: MDef => d.defType == DRecord && idSwift.ty(d.name) == name
    case e: MExtern => e.defType == DRecord && e.swift.typename == name
    case _ => false
  }

  // True when the type has the Swift name of the error record, whatever kind of type it is.
  def hasErrorName(tm: MExpr, name: String): Boolean = tm.base match {
    case d: MDef => idSwift.ty(d.name) == name
    case e: MExtern => e.swift.typename == name
    case p: MProtobuf => p.body.swift.exists(o => o.prefix + p.name == name)
    case _ => false
  }

  def isFuture(tm: MExpr): Boolean = tm.base match {
    case e: MExtern => e.name == "future" && tm.args.size == 1
    case _ => false
  }

  // True when the type holds a DataRef (shared, mutable memory) or a DataView (memory that C++ owns), also in a
  // record or in a type argument. No value of such a type is Sendable. A record can hold itself through a list, so the
  // records that the search has entered are not entered again.
  def holdsBuffer(tm: MExpr): Boolean = holdsBuffer(tm, Set())

  private def holdsBuffer(tm: MExpr, entered: Set[String]): Boolean = tm.args.exists(holdsBuffer(_, entered)) || (tm.base match {
    case e: MExtern => e.name == "DataRef" || e.name == "DataView"
    case d: MDef if entered.contains(d.name) => false
    case d: MDef => d.body match {
      case r: Record => r.fields.exists(f => holdsBuffer(f.ty.resolved, entered + d.name))
      case _ => false
    }
    case _ => false
  })

  // True when a value of the type can cross into a closure that runs on another queue.
  def isSendableArgument(tm: MExpr): Boolean = if (holdsBuffer(tm)) false else tm.base match {
    case d: MDef if d.defType == DInterface => true
    case MOptional | MList | MArray | MSet | MMap => tm.args.forall(isSendableArgument)
    case _ => isSendable(tm)
  }

  // True when Swift can check that the type is Sendable. False when the generator has to trust it.
  def isSendable(tm: MExpr): Boolean = tm.base match {
    case _: MPrimitive | MString | MDate | MBinary | MVoid => true
    case MOptional | MList | MArray | MSet | MMap => tm.args.forall(isSendable)
    // Generated protocols are AnyObject, Sendable, so a record with an interface field stays checked
    case d: MDef => true
    case _: MProtobuf => true
    case e: MExtern =>
      if (e.defType == DInterface) false
      else if (e.swift.translator.startsWith("ProtobufMarshaller")) true
      else if (e.swift.typename == "Result" || e.swift.typename == "Swift.Result") tm.args.forall(isSendable)
      else if (e.swift.typename == "DJFuture") tm.args.forall(isSendable)
      else false
    case _: MParam => false
  }

  private def withPackage(packageName: Option[String], t: String) = packageName.fold(t)(_ + "." + t)

  def references(m: Meta, exclude: String = ""): Seq[SymbolReference] = m match {
    case MProtobuf(name, _, ProtobufMessage(_,_,_,_,Some(swift))) => List(ImportRef(swift.module), PrivateImportRef(swift.module))
    case d: MDef => List()
    case e: MExtern => List(ImportRef(e.swift.module), PrivateImportRef(e.swift.module), PrivateImportRef(e.swift.translatorModule))
    case _ => List()
  }

  private def toSwiftType(tm: MExpr, packageName: Option[String]): String = {
    def args(tm: MExpr) = if (tm.args.isEmpty) "" else tm.args.map(f(_)).mkString("<", ", ", ">")
    def f(tm: MExpr): String = {
      tm.base match {
        case MOptional =>
          assert(tm.args.size == 1)
          val arg = tm.args.head
          arg.base match {
            case MOptional => throw new AssertionError("nested optional?")
            case m => s"Optional<${f(arg)}>"
          }
        case e: MExtern =>
          val supportModule = SwiftSupport.publicModule(spec.swiftCxxFreeApi, e.swift.module, e.swift.typename)
          Array(supportModule, e.swift.typename).filter(s => !s.isEmpty).mkString(".") + (if (e.swift.generic) args(tm) else "")
        case p: MProtobuf => p.body.swift match {
          case Some(o) => o.prefix + p.name
          case None => throw GenerateException(SwiftProtobuf.message(p.name))
        }
        case o =>
          val base = o match {
            case p: MPrimitive => swiftPrimitiveType(p)
            case MString => "String"
            case MDate => "Date"
            case MBinary => "Data"
            case MOptional => throw new AssertionError("optional should have been special cased")
            case MList => "Array"
            case MArray => "Array"
            case MSet => "Set"
            case MMap => "Dictionary"
            case d: MDef => withPackage(packageName, idSwift.ty(d.name))
            case e: MExtern => throw new AssertionError("unreachable")
            case e: MProtobuf => throw new AssertionError("unreachable")
            case p: MParam => idSwift.typeParam(p.name)
            case MVoid => "Void"
          }
          base + args(tm)
      }
    }
    f(tm)
  }

  private def swiftPrimitiveType(p: MPrimitive): String = p._idlName match {
    case "bool" => "Bool"
    case "i64" => "Int64"
    case "i32" => "Int32"
    case "i16" => "Int16"
    case "i8" => "Int8"
    case "f32" => "Float"
    case "f64" => "Double"
    case _ => throw new AssertionError("unknown primitive type: " + p._idlName)
  }

  def helperClass(name: String) = idSwift.ty(name) + "Marshaller" // TODO: [MOB-6413] make the marshaller name configurable
  private def helperClass(tm: MExpr): String = helperName(tm) + helperTemplates(tm)
  def helperName(tm: MExpr): String = tm.base match {
    case d: MDef => helperClass(d.name)
    case e: MExtern => Array(e.swift.translatorModule, e.swift.translator).filter(s => !s.isEmpty).mkString(".")
    case o => o match {
      case p: MPrimitive => p.idlName match {
        case "i8" => "I8Marshaller"
        case "i16" => "I16Marshaller"
        case "i32" => "I32Marshaller"
        case "i64" => "I64Marshaller"
        case "f32" => "F32Marshaller"
        case "f64" => "F64Marshaller"
        case "bool" => "BoolMarshaller"
      }
      case MOptional => "OptionalMarshaller"
      case MBinary => "BinaryMarshaller"
      case MString => "StringMarshaller"
      case MDate => "DateMarshaller"
      case MList => "ListMarshaller"
      case MSet => "SetMarshaller"
      case MMap => "MapMarshaller"
      case p: MProtobuf => p.body.swift match {
        case Some(o) => "ProtobufMarshaller<" + o.prefix + p.name + ">"
        case None => throw GenerateException(SwiftProtobuf.message(p.name))
      }
      case MArray => "ArrayMarshaller"
      case d: MDef => throw new AssertionError("unreachable")
      case e: MExtern => throw new AssertionError("unreachable")
      case p: MParam => throw new AssertionError("not applicable")
      case MVoid => "Void_Marshaller"
    }
  }
  private def helperTemplates(tm: MExpr): String = {
    def f() = if(tm.args.isEmpty) "" else tm.args.map(helperClass).mkString("<", ", ", ">")
    tm.base match {
      case MOptional | MList | MSet | MArray =>
        assert(tm.args.size == 1)
        f
      case _ => f
    }
  }
}
