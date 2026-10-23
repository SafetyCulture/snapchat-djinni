load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "swift-protobuf",
    srcs = glob(["Sources/SwiftProtobuf/**/*.swift"]),
    module_name = "SwiftProtobuf",
    # SwiftProtobuf 1.38 uses package access inside its own module
    package_name = "SwiftProtobuf",
    visibility = ["//visibility:public"],
)
