#!/usr/bin/env bash
# Builds and runs a Swift program against a C++ implementation of generated interfaces.
#
# The program checks the runtime: calls from Swift into C++, calls from C++ into a Swift object,
# the identity of proxies, and many threads that create and release proxies and host objects.
# It runs in Swift 5 mode and in Swift 6 mode. A watchdog fails the program when it deadlocks. macOS only.
#
# Environment:
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   RUNS               runs of the program in each mode (default: 3)
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
src="$repo_root/ci/swift-runtime"
runs="${RUNS:-3}"
cache="${SWIFT_CACHE:-$HOME/.cache/djinni-swift}"
work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-runtime.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

# SwiftProtobuf is a dependency of DjinniSupport. It is built once per compiler.
spb_mod="$cache/spb-1.38.1-$(swiftc --version | shasum -a 256 | cut -d' ' -f1)"
if [ ! -f "$spb_mod/libSwiftProtobuf.a" ]; then
  mkdir -p "$cache" "$spb_mod"
  # The sources of one tag stay in their own directory; a tag bump never reuses stale sources
  if [ ! -d "$cache/swift-protobuf-1.38.1" ]; then
    # Pinned archive: a moved tag cannot change the sources
    curl -fsSL --retry 3 -o "$cache/swift-protobuf-1.38.1.tar.gz" https://github.com/apple/swift-protobuf/archive/refs/tags/1.38.1.tar.gz
    [ "$(shasum -a 256 "$cache/swift-protobuf-1.38.1.tar.gz" | cut -d' ' -f1)" = "7e35c119afe8f16fe4de45c2143b0f50a205db83738092336562d610469283ac" ] || { echo "SHA-256 of the SwiftProtobuf archive differs" >&2; exit 1; }
    tar -xzf "$cache/swift-protobuf-1.38.1.tar.gz" -C "$cache"
  fi
  swiftc -emit-library -static -emit-module -emit-module-path "$spb_mod/SwiftProtobuf.swiftmodule" -o "$spb_mod/libSwiftProtobuf.a" \
    -module-name SwiftProtobuf -parse-as-library -swift-version 5 -package-name SwiftProtobuf -wmo -Onone "$cache"/swift-protobuf-1.38.1/Sources/SwiftProtobuf/*.swift
fi

out="$work/out"
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime.djinni)
# The error type needs its own IDL, because every method of a C++ interface must return an outcome.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-error-type CruxError \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_error.djinni)

# Legacy records have var fields. The record crosses the C++ boundary in both directions.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-legacy-records \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_legacy.djinni)

# Modules
mods="$work/mods"; build="$work/build"
mkdir -p "$mods" "$build"
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$mods/RuntimeTestCxx.hpp" "$out/swiftxx"
cat >"$mods/module.modulemap" <<EOF
module DjinniSupportCxx {
  header "$repo_root/support-lib/swiftxx/djinni_support.hpp"
  header "$repo_root/support-lib/swiftxx/Future_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Data_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Outcome_swift.hpp"
  requires cplusplus
  export *
}
module RuntimeTestCxx {
  header "$mods/RuntimeTestCxx.hpp"
  requires cplusplus
  export *
}
EOF

# C++: the support library, the generated glue and the implementation
objs="$work/objs"
mkdir -p "$objs"
cxxflags=(-std=c++20 -Wno-deprecated-declarations -DDATAREF_OBJC=1 -I "$out/cpp" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib")
for f in "$repo_root"/support-lib/swiftxx/*.cpp "$repo_root/support-lib/objc/DataRef_objc.cpp" "$out"/swiftxx/*.cpp "$src/runtime_service_impl.cpp" "$src/runtime_async_impl.cpp" "$src/error_service_impl.cpp" "$src/legacy_service_impl.cpp"; do
  "${CXX:-clang++}" "${cxxflags[@]}" -c "$f" -o "$objs/$(basename "$f").o"
done

# Swift: DjinniSupport as a static library, then the program. Each mode has its own build.
run_mode() { # <swiftc flags>
  local flags=$1 build
  build="$work/build-$(echo "$flags" | tr -c 'a-z0-9\n' _)"
  mkdir -p "$build"
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$mods" -I "$build" -I "$spb_mod")
  echo "== [$flags]"
  # shellcheck disable=SC2086
  swiftc -emit-library -static -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -parse-as-library $flags "${cxx[@]}" "$repo_root"/support-lib/swift/*.swift -o "$build/libDjinniSupport.a"
  # shellcheck disable=SC2086
  swiftc -module-name RuntimeTest $flags "${cxx[@]}" "$out"/swift/*.swift "$src/main.swift" \
    "$objs"/*.o "$build/libDjinniSupport.a" "$spb_mod/libSwiftProtobuf.a" -Xlinker -framework -Xlinker CoreFoundation -o "$build/runtime-test"
  local i
  for i in $(seq 1 "$runs"); do
    "$build/runtime-test"
  done
}
run_mode "-swift-version 5"
run_mode "-swift-version 6 -strict-concurrency=complete"
