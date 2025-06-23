package djinni

import ast.{Interface}

class KMPUtils {
  // filter for supported interface methods
  def supportedMethods(i: Interface): Seq[Interface.Method] = {
    i.methods
    .filterNot(_.static) // no static method support
  }
}
