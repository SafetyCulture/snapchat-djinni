load("@rules_cc//cc:defs.bzl", "cc_library", "objc_library")
load("@rules_java//java:defs.bzl", "java_library")

cc_library(
    name = "djinni-support-common",
    srcs = glob(["cpp/*.cpp"]),
    hdrs = glob(["*.hpp", "cpp/*.hpp"]),
    includes = ["cpp"],
    visibility = ["//visibility:public"],
)

cc_library(
    name = "djinni-support-jni",
    srcs = glob(["jni/*.cpp"]),
    hdrs = glob(["jni/*.hpp"]),
    includes = ["jni"],
    defines = ["DATAREF_JNI=1"],
    linkstatic = True,
    visibility = ["//visibility:public"],
    deps = [
        "//support-lib:djinni-support-common",
        "@bazel_tools//tools/jdk:jni",
    ],
    alwayslink = 1,
)

cc_library(
    name = "djinni-support-android",
    srcs = glob(["jni/*.cpp"]),
    hdrs = glob(["jni/*.hpp"]),
    includes = ["jni"],
    defines = ["DATAREF_JNI=1"],
    visibility = ["//visibility:public"],
    deps = [
        "//support-lib:djinni-support-common",
    ],
    alwayslink = 1,
)

objc_library(
    name = "djinni-support-objc",
    srcs = glob(["objc/*.mm", "objc/*.cpp"], exclude = ["objc/DataRef_objc.cpp"]),
    hdrs = glob(["objc/*.h", "objc/*.hpp"]),
    copts = [
        "-ObjC++",
    ],
    includes = ["objc"],
    defines = ["DATAREF_OBJC=1"],
    visibility = ["//visibility:public"],
    deps = [
        "//support-lib:djinni-support-common",
        "//support-lib:djinni-support-dataref-apple",
    ],
)

java_library(
    name = "djinni-support-java",
    srcs = glob(["java/**/*.java"]),
    visibility = ["//visibility:public"],
)

cc_library(
    name = "djinni-support-wasm",
    srcs = glob(["wasm/*.cpp"]),
    hdrs = glob(["wasm/*.hpp"]),
    includes = ["wasm"],
    defines = ["DATAREF_WASM=1"],
    visibility = ["//visibility:public"],
    copts = [
        "-fexceptions",
    ],
    deps = [
        "//support-lib:djinni-support-common",
    ],
)

sh_library(
    name = "djinni-support-ts",
    data = glob(["ts/*.ts"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "swift-sources",
    srcs = glob(["swift/*.swift"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "swiftxx-headers",
    srcs = glob(["swiftxx/*.hpp"]),
    visibility = ["//visibility:public"],
)

# The DataRef constructors for Apple platforms, shared by the ObjC and the Swift runtime.
cc_library(
    name = "djinni-support-dataref-apple",
    srcs = ["objc/DataRef_objc.cpp"],
    defines = ["DATAREF_OBJC=1"],
    visibility = ["//visibility:public"],
    deps = [":djinni-support-common"],
)

cc_library(
    name = "djinni-support-swiftxx-core",
    srcs = glob(["swiftxx/*.cpp"]),
    hdrs = glob(["swiftxx/*.hpp"]),
    copts = ["-std=c++20", "-Wno-deprecated-declarations"],
    defines = ["DATAREF_OBJC=1"],
    includes = [
        ".",
        "swiftxx",
    ],
    visibility = ["//visibility:public"],
    deps = [
        ":djinni-support-common",
        ":djinni-support-dataref-apple",
    ],
)
