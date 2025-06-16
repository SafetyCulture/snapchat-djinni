package djinni

import ast.{TypeRef, Interface}
import meta.MExtern

class KMPUtils {
  // check if we support this interface
  def isNotSupported(i: Interface): Boolean = {
    !i.ext.cpp || i.ext.java || i.ext.objc || i.ext.js
  }

  // filter for supported interface methods
  def supportedMethods(i: Interface): Seq[Interface.Method] = {
    i.methods
    .filterNot(_.static)
    .filterNot(m => {
      val containsUnsupportedParam = m.params.map(_.ty).exists(isNotSupported)
      val containsUnsupportedReturn = m.ret.exists(isNotSupported)
      containsUnsupportedParam || containsUnsupportedReturn
    })
  }

  def isNotSupported(ty: TypeRef): Boolean = ty.resolved.base match {
    // no support for parameters of an external type that isn't a protobuf message
    case e: MExtern if !e.kotlin.isProtobufMessage => true
    case _ => false
  }
}
