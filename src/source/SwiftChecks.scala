package djinni

import djinni.ast._
import djinni.ast.Record.DerivingType
import djinni.generatorTools._
import djinni.meta._

// Inputs that give Swift or Swift/C++ glue that does not compile. The checks run before any generator writes a file.
// Each message names the type, the member and the rule that the input breaks.
object SwiftChecks {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val interns = idl.collect { case d: InternTypeDecl => d }
    val swiftxx = if (spec.swiftxxOutFolder.isDefined) futureFieldProblems(interns) ++ fileNameProblems(interns, spec) else Seq()
    val swift = if (spec.swiftOutFolder.isDefined) {
      moduleNameProblems(interns, spec) ++ outcomeErrorProblems(interns, spec) ++ codableProblems(interns) ++ reservedNameProblems(interns, spec) ++ constantProblems(interns)
    } else Seq()
    val all = swiftxx ++ swift
    if (all.isEmpty) None else Some(all.mkString("\n"))
  }

  // Every type expression of the IDL, with the place that it is in, and whether it is the result of a method.
  private def typeExprs(td: InternTypeDecl): Seq[(String, MExpr, Boolean)] = td.body match {
    case r: Record =>
      r.fields.map(f => (s"record ${td.ident.name}, field ${f.ident.name}", f.ty.resolved, false)) ++
        r.consts.map(c => (s"record ${td.ident.name}, constant ${c.ident.name}", c.ty.resolved, false))
    case i: Interface =>
      i.methods.flatMap(m => m.params.map(p => (s"interface ${td.ident.name}, method ${m.ident.name}, parameter ${p.ident.name}", p.ty.resolved, false)) ++
        m.ret.map(t => (s"interface ${td.ident.name}, method ${m.ident.name}", t.resolved, true))) ++
        i.consts.map(c => (s"interface ${td.ident.name}, constant ${c.ident.name}", c.ty.resolved, false))
    case _ => Seq()
  }

  private def subExprs(tm: MExpr): Seq[MExpr] = tm +: tm.args.flatMap(subExprs)

  private def isExtern(tm: MExpr, name: String): Boolean = tm.base match {
    case e: MExtern => e.name == name
    case _ => false
  }

  // The Swift/C++ glue of a record copies its fields, and a C++ future cannot be copied.
  private def futureFieldProblems(interns: Seq[InternTypeDecl]): Seq[String] = for {
    td <- interns
    r <- Seq(td.body).collect { case r: Record => r }
    f <- r.fields if subExprs(f.ty.resolved).exists(isExtern(_, "future"))
  } yield s"record ${td.ident.name}, field ${f.ident.name}: the Swift/C++ glue of a record cannot copy a future<>. Use a future<> only as the result of a method."

  // The glue header of a type includes the C++ header of the type. With equal file names and no include prefix, the
  // glue header includes itself, and a glue file overwrites a C++ file when the folders are the same.
  private def fileNameProblems(interns: Seq[InternTypeDecl], spec: Spec): Seq[String] = {
    val sameNames = interns.exists(td => spec.swiftxxFileIdentStyle(td.ident.name) == spec.cppFileIdentStyle(td.ident.name))
    def canonical(f: java.io.File) = f.getCanonicalPath
    val sameFolder = sameNames && spec.swiftxxOutFolder.exists(out =>
      (spec.cppOutFolder.toSeq ++ spec.cppHeaderOutFolder.toSeq).exists(cpp => canonical(cpp) == canonical(out)))
    val include = if (sameNames && spec.swiftxxIncludeCppPrefix.isEmpty) {
      Seq("--swiftxx-out writes glue headers with the names of the C++ headers, and --swiftxx-include-cpp-prefix is empty, so a glue header includes itself. Set --swiftxx-include-cpp-prefix, or set --ident-swiftxx-file.")
    } else Seq()
    val folder = if (sameFolder) {
      Seq("--swiftxx-out is the output folder of the C++ code, and the glue files have the names of the C++ files, so they overwrite each other. Use another folder, or set --ident-swiftxx-file.")
    } else Seq()
    include ++ folder
  }

  // The generated Swift names a type with the module name in front. A type with the name of the module hides the
  // module in that name, so every reference breaks.
  private def moduleNameProblems(interns: Seq[InternTypeDecl], spec: Spec): Seq[String] =
    interns.filter(td => spec.swiftIdentStyle.ty(td.ident.name) == spec.swiftModule).map { td =>
      s"${td.ident.name} is ${spec.swiftModule} in Swift, the name of the Swift module. The generated code names a type with the module in front, so the type hides the module. Rename the type, or set --swift-module."
    }

  // Swift's Result needs an error type that conforms to Error. The generator adds that conformance to a record
  // that derives error, and to the record of --swift-error-type.
  private def outcomeErrorProblems(interns: Seq[InternTypeDecl], spec: Spec): Seq[String] = {
    def notError(e: MExpr): Option[String] = e.base match {
      case d: MDef => d.defType match {
        case DRecord =>
          val derivesError = d.body match {
            case r: Record => r.derivingTypes.contains(DerivingType.Error)
            case _ => false
          }
          if (derivesError || spec.swiftErrorType.contains(spec.swiftIdentStyle.ty(d.name))) None
          else Some(s"the record ${d.name} does not derive error")
        case DEnum => Some(s"the enum ${d.name} does not conform to Error")
        case DInterface => Some(s"the interface ${d.name} does not conform to Error")
      }
      case p: MProtobuf => Some(s"the protobuf message ${p.name} does not conform to Error")
      case _: MOpaque => Some(s"the type ${e.base.asInstanceOf[MOpaque].idlName} does not conform to Error")
      case _ => None
    }
    for {
      td <- interns
      (where, tm, isResult) <- typeExprs(td)
      // With --swift-error-type, SwiftErrorType checks the results of the methods and names the error type
      if !(isResult && spec.swiftErrorType.isDefined)
      outcome <- subExprs(tm) if isExtern(outcome, "outcome") && outcome.args.size == 2
      why <- notError(outcome.args(1))
    } yield s"$where: the error type of outcome<T, E> must conform to Error in Swift, but $why. Add deriving(error) to the record."
  }


  // The generator adds Codable to enums, flags and records with deriving(codable). Swift cannot synthesize it for a
  // field of these types.
  private def codableProblems(interns: Seq[InternTypeDecl]): Seq[String] = {
    def notCodable(e: MExpr): Option[String] = e.base match {
      case d: MDef if d.defType == DInterface => Some(s"the interface ${d.name} is not Codable")
      case p: MProtobuf => Some(s"the protobuf message ${p.name} is not Codable")
      case x: MExtern if x.defType == DInterface || Set("outcome", "future", "DataRef", "DataView").contains(x.name) =>
        Some(s"the type ${x.name} is not Codable")
      case _ => None
    }
    for {
      td <- interns
      r <- Seq(td.body).collect { case r: Record if r.derivingTypes.contains(DerivingType.Codable) => r }
      f <- r.fields
      why <- subExprs(f.ty.resolved).flatMap(e => notCodable(e)).headOption
    } yield s"record ${td.ident.name}, field ${f.ident.name}: deriving(codable) needs a Codable type, but $why."
  }

  // The wrapper of --swift-async-wrap names its locals and members djinniXxx. An IDL name that Swift writes the same
  // way hides one of them.
  private def reservedNameProblems(interns: Seq[InternTypeDecl], spec: Spec): Seq[String] = {
    if (spec.swiftAsyncWrap.isEmpty) return Seq()
    val reserved = "djinni[A-Z].*".r
    for {
      td <- interns
      i <- Seq(td.body).collect { case i: Interface if i.ext.cpp && !i.ext.swift => i }
      m <- i.methods if !m.static
      (kind, name, swiftName) <- Seq(("method", m.ident.name, spec.swiftIdentStyle.method(m.ident.name))) ++
        m.params.map(p => ("parameter", p.ident.name, spec.swiftIdentStyle.local(p.ident.name)))
      if reserved.pattern.matcher(SwiftIdent.plain(swiftName)).matches
    } yield s"interface ${td.ident.name}, method ${m.ident.name}: the $kind name $name is $swiftName in Swift. --swift-async-wrap uses names that start with djinni and a capital letter inside the wrapper, so rename it."
  }

  // A Swift string literal has other escapes than a Java one.
  private def constantProblems(interns: Seq[InternTypeDecl]): Seq[String] = {
    def strings(v: Any): Seq[String] = v match {
      case s: String => Seq(s)
      case m: Map[_, _] => m.values.toSeq.flatMap(strings)
      case _ => Seq()
    }
    for {
      td <- interns
      c <- td.body match {
        case r: Record => r.consts
        case i: Interface => i.consts
        case _ => Seq()
      }
      s <- strings(c.value)
      problem <- SwiftLiteral.convert(s).left.toOption
      kind = if (td.body.isInstanceOf[Record]) "record" else "interface"
    } yield s"$kind ${td.ident.name}, constant ${c.ident.name}: $problem"
  }
}

object SwiftLiteral {
  // `raw` is the string constant as the IDL has it, with its quotes and its Java escapes.
  // Swift knows the escapes for NUL, tab, newline, return, the two quotes and the backslash, and a Unicode scalar in
  // braces. The other Java escapes (a four digit Unicode escape, backspace, form feed, octal) are written as a scalar.
  def convert(raw: String): Either[String, String] = {
    val body = raw.substring(1, raw.length - 1)
    val out = new StringBuilder
    var i = 0
    def hex4(at: Int): Option[Int] =
      if (at + 4 <= body.length && body.substring(at, at + 4).matches("[0-9a-fA-F]{4}")) Some(Integer.parseInt(body.substring(at, at + 4), 16)) else None
    def scalar(code: Int) = "\\u{" + Integer.toHexString(code).toUpperCase + "}"
    while (i < body.length) {
      val c = body.charAt(i)
      if (c != '\\') { out.append(c); i += 1 }
      else if (i + 1 >= body.length) return Left(s"the string ends with a single backslash")
      else {
        val e = body.charAt(i + 1)
        e match {
          case 'n' | 't' | 'r' | '"' | '\'' | '\\' => out.append('\\').append(e); i += 2
          case 'b' => out.append(scalar(8)); i += 2
          case 'f' => out.append(scalar(12)); i += 2
          case 's' => out.append(scalar(32)); i += 2
          case 'u' =>
            hex4(i + 2) match {
              case None => return Left("the escape \\u needs four hexadecimal digits")
              case Some(unit) if Character.isHighSurrogate(unit.toChar) =>
                val low = if (body.startsWith("\\u", i + 6)) hex4(i + 8) else None
                low match {
                  case Some(l) if Character.isLowSurrogate(l.toChar) =>
                    out.append(scalar(Character.toCodePoint(unit.toChar, l.toChar))); i += 12
                  case _ => return Left("the escape \\u" + body.substring(i + 2, i + 6) + " is a surrogate without its pair, which Swift cannot write")
                }
              case Some(unit) if Character.isLowSurrogate(unit.toChar) =>
                return Left("the escape \\u" + body.substring(i + 2, i + 6) + " is a surrogate without its pair, which Swift cannot write")
              case Some(unit) => out.append(scalar(unit)); i += 6
            }
          case d if d >= '0' && d <= '7' =>
            val max = if (d <= '3') 3 else 2
            var j = i + 1
            while (j < body.length && j - (i + 1) < max && body.charAt(j) >= '0' && body.charAt(j) <= '7') j += 1
            val code = Integer.parseInt(body.substring(i + 1, j), 8)
            if (code == 0 && j == i + 2) out.append("\\0") else out.append(scalar(code))
            i = j
          case other => return Left(s"the escape \\$other is not a Swift escape")
        }
      }
    }
    Right("\"" + out + "\"")
  }
}
