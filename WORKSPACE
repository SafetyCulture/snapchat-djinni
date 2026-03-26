workspace(name="snap_djinni")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "zlib",
    sha256 = "17e88863f3600672ab49182f217281b6fc4d3c762bde361935e436a95214d05c",
    strip_prefix = "zlib-1.3.1",
    urls = ["https://github.com/madler/zlib/archive/v1.3.1.tar.gz"],
    build_file = "@//:bzl/zlib.BUILD",  # override build with our own to suppress warnings
)

load("//bzl:deps.bzl", "djinni_deps")
djinni_deps()
load("//bzl:scala_config.bzl", "djinni_scala_config")
djinni_scala_config()
load("//bzl:setup_deps.bzl", "djinni_setup_deps")
djinni_setup_deps()

# --- Everything below is only used for examples and tests