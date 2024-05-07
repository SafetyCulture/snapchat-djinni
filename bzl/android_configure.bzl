"""Repository rule for Android SDK and NDK autoconfiguration.

This rule is a no-op unless the required android environment variables are set.
"""

# Based on: https://github.com/envoyproxy/envoy-mobile/pull/2039/
# And: https://github.com/tensorflow/tensorflow/tree/34c03ed67692eb76cb3399cebca50ea8bcde064c/third_party/android
# Workaround for https://github.com/bazelbuild/bazel/issues/14260

_ANDROID_NDK_HOME = "ANDROID_NDK_HOME"
_ANDROID_SDK_HOME = "ANDROID_HOME"

def _android_autoconf_impl(repository_ctx):
    sdk_home = repository_ctx.os.environ.get(_ANDROID_SDK_HOME)
    ndk_home = repository_ctx.os.environ.get(_ANDROID_NDK_HOME)

    if sdk_home == "" or ndk_home == "":
        print("ANDROID_HOME or ANDROID_NDK_HOME not set. Building android examples will fail.")

    sdk_rule = ""
    if sdk_home:
        sdk_rule = """
    native.android_sdk_repository(
        name="androidsdk",
        path="{}",
    )
""".format(sdk_home)

    ndk_rule = ""
    if ndk_home:
        ndk_rule = """
    native.android_ndk_repository(
        name="androidndk",
        path="{}",
        api_level=21,
    )
""".format(ndk_home)

    if ndk_rule == "" and sdk_rule == "":
        sdk_rule = "pass"

    repository_ctx.file("BUILD.bazel", "")
    repository_ctx.file("android_configure.bzl", """
    
def android_workspace():
    {}
    {}
    """.format(sdk_rule, ndk_rule))

android_configure = repository_rule(
    implementation = _android_autoconf_impl,
    environ = [
        _ANDROID_NDK_HOME,
        _ANDROID_SDK_HOME,
    ],
)
