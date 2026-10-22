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

// Checks --swift-error-type: every instance method of a C++ interface returns outcome<T, E>.
object SwiftErrorType {
  def check(idl: Seq[TypeDecl], spec: Spec): Option[String] = {
    val name = spec.swiftErrorType.get
    val marshal = new SwiftMarshal(spec)
    val problems = for {
      td <- idl
      i <- td.body match { case i: Interface => Seq(i); case _ => Seq() }
      if i.ext.cpp
      m <- i.methods if !m.static
      problem <- methodProblem(marshal, td.ident.name, m, name)
    } yield problem
    if (problems.isEmpty) None else Some(problems.mkString("\n"))
  }

  private def methodProblem(marshal: SwiftMarshal, interface: String, m: Interface.Method, name: String): Option[String] = {
    val where = s"interface $interface, method ${m.ident.name}"
    // An outcome, or a future of an outcome.
    val outcome = m.ret.map(_.resolved).flatMap { tm =>
      if (marshal.isOutcome(tm)) Some(tm)
      else if (marshal.isFuture(tm) && marshal.isOutcome(tm.args.head)) Some(tm.args.head)
      else None
    }
    outcome match {
      case None => Some(s"$where: --swift-error-type needs a return type outcome<T, $name>")
      case Some(tm) if !marshal.isErrorRecord(tm.args(1), name) =>
        Some(s"$where: the error type of the outcome is ${marshal.typename(tm.args(1))}, but --swift-error-type is $name")
      case _ => None
    }
  }
}
