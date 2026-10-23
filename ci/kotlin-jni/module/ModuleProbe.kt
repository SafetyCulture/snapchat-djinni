// The first call loads the class, so its companion runs the module initializer before the native call.
fun main() {
    try {
        KotlinJniModuleProbe.create()
    } catch (e: UnsatisfiedLinkError) {
        println("module initializer: the module class without a package loads")
        return
    }
    throw AssertionError("the native method ran without a native library")
}
