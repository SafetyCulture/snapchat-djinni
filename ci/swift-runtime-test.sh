#!/usr/bin/env bash
# Builds and runs a Swift program against a C++ implementation of generated interfaces.
#
# The program checks the runtime: calls from Swift into C++, calls from C++ into a Swift object,
# the identity of proxies, and many threads that create and release proxies and host objects.
# It runs in Swift 5 mode, in Swift 6 mode, and in Swift 6 mode with the optimizer (-O, and -O2 for C++). It also runs
# once with ThreadSanitizer for Swift and C++. The last variant generates the same IDL with
# --swift-internal-cxx-imports and --swift-cxx-free-api, builds the generated module with library evolution, and runs
# the same program. A watchdog fails the program when it deadlocks. macOS only.
#
# Environment:
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   RUNS               runs of the program in each mode (default: 3; the ThreadSanitizer mode runs once)
#   RUNTIME_TSAN       set to 0 to skip the ThreadSanitizer mode
#   RUNTIME_TIMEOUT    seconds after which a run of the program is killed (default: 300)
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
# The queue of the application runs the blocking C++ calls; the other runs use the default queue.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-async-queue RuntimeQueues.blocking \
  --swift-sync-method runtime_async.register_listener \
  --swift-sync-method runtime_async.record_pair \
  --swift-sync-method runtime_async.recorded_pair \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime.djinni)
# The error type has its own IDL: every method that Swift calls into C++ throws it.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-error-type CruxError \
  --swift-sync-method error_service.register_listener \
  --swift-sync-method error_service.register_listener_failing \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_error.djinni)
# Without the async wrappers the protocol methods throw the error type.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module \
  --swift-error-type SyncError \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_error_sync.djinni)

# Swift calls the make function of a Swift proxy directly, so it needs an exception boundary
made=0
for f in "$out"/swiftxx/*.cpp; do
  if grep -q '::make(void\* instance' "$f"; then
    made=$((made + 1))
    if ! grep -A12 '::make(void\* instance' "$f" | grep -q 'catch (\.\.\.)'; then
      echo "FAIL: the make function in $f has no catch (...)" >&2
      exit 1
    fi
  fi
done
[ "$made" -gt 0 ] || { echo "FAIL: no make function was generated" >&2; exit 1; }

# Legacy records have var fields. The record crosses the C++ boundary in both directions.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace rt \
  --swift-out "$out/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-legacy-records \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_legacy.djinni)

# The same program with the default queue: runtime.djinni without --swift-async-queue replaces its files.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$work/default/cpp" --cpp-namespace rt \
  --swift-out "$work/default/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-sync-method runtime_async.register_listener \
  --swift-sync-method runtime_async.record_pair \
  --swift-sync-method runtime_async.recorded_pair \
  --idl runtime.djinni)
cp -R "$out/swift" "$out/swift-default"
cp "$work"/default/swift/*.swift "$out/swift-default/"

# --swift-sync-method gives the listed registrations a synchronous form. The future method with a +sw parameter that
# is not listed gets none.
now_forms() { grep -hoE "public func [A-Za-z0-9]+Now\(" "$1" | LC_ALL=C sort; }
if [ "$(now_forms "$out/swift/RuntimeAsync.swift")" != "public func recordPairNow(
public func recordedPairNow(
public func registerListenerNow(" ]; then
  echo "FAIL: RuntimeAsync does not have the three synchronous forms that are listed." >&2
  now_forms "$out/swift/RuntimeAsync.swift" >&2
  exit 1
fi
if ! grep -qF "return try djinniProxy.registerListener(listener)" "$out/swift/RuntimeAsync.swift"; then
  echo "FAIL: the synchronous registration does not call the proxy on the thread of the caller." >&2
  exit 1
fi
if [ "$(now_forms "$out/swift/ErrorService.swift")" != "public func registerListenerFailingNow(
public func registerListenerNow(" ]; then
  echo "FAIL: ErrorService does not have the two synchronous forms that are listed." >&2
  now_forms "$out/swift/ErrorService.swift" >&2
  exit 1
fi
if ! grep -qF "public func registerListenerNow(_ listener: RuntimeTest.ErrorListener) throws(RuntimeTest.CruxError) -> Int32 {" "$out/swift/ErrorService.swift"; then
  echo "FAIL: the synchronous registration does not throw the error type." >&2
  exit 1
fi
if ! grep -qF "return try DjinniSupport.djinniTyped(RuntimeTest.CruxError.self) { try djinniProxy.registerListener(listener) }" "$out/swift/ErrorService.swift"; then
  echo "FAIL: the synchronous registration with the error type does not call the proxy directly." >&2
  exit 1
fi

# The same four IDLs with the option that keeps the C++ types out of the public API of the generated module.
out_cxx_free="$work/cxx-free"
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out_cxx_free/cpp" --cpp-namespace rt \
  --swift-out "$out_cxx_free/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-sync-method runtime_async.register_listener \
  --swift-sync-method runtime_async.record_pair \
  --swift-sync-method runtime_async.recorded_pair \
  --swift-async-queue 'DispatchQueue(label: "djinni.runtime.blocking", attributes: .concurrent)' \
  --swiftxx-out "$out_cxx_free/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime.djinni)
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out_cxx_free/cpp" --cpp-namespace rt \
  --swift-out "$out_cxx_free/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-sync-method error_service.register_listener \
  --swift-sync-method error_service.register_listener_failing \
  --swift-error-type CruxError \
  --swiftxx-out "$out_cxx_free/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_error.djinni)
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out_cxx_free/cpp" --cpp-namespace rt \
  --swift-out "$out_cxx_free/swift" --swift-module RuntimeTest --swift-private-in-same-module \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-error-type SyncError \
  --swiftxx-out "$out_cxx_free/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_error_sync.djinni)
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out_cxx_free/cpp" --cpp-namespace rt \
  --swift-out "$out_cxx_free/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-legacy-records \
  --swiftxx-out "$out_cxx_free/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl runtime_legacy.djinni)
# The same program with the default queue: runtime.djinni without --swift-async-queue replaces its files.
(cd "$src" && java -jar "$jar" \
  --cpp-out "$work/cxx-free-default/cpp" --cpp-namespace rt \
  --swift-out "$work/cxx-free-default/swift" --swift-module RuntimeTest --swift-private-in-same-module --swift-async-wrap djinni.runtime \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-sync-method runtime_async.register_listener \
  --swift-sync-method runtime_async.record_pair \
  --swift-sync-method runtime_async.recorded_pair \
  --idl runtime.djinni)
cp -R "$out_cxx_free/swift" "$out_cxx_free/swift-default"
cp "$work"/cxx-free-default/swift/*.swift "$out_cxx_free/swift-default/"
# The option changes the Swift files only.
if ! diff -r "$out/swiftxx" "$out_cxx_free/swiftxx"; then
  echo "FAIL: --swift-cxx-free-api changed the C++ glue." >&2
  exit 1
fi

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
cxxflags=(-std=c++20 -Wno-deprecated-declarations -DDATAREF_OBJC=1 -I "$out/cpp" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib")
build_objs() { # <object folder> [C++ flags]
  local dir=$1 f
  shift
  mkdir -p "$dir"
  for f in "$repo_root"/support-lib/swiftxx/*.cpp "$repo_root/support-lib/objc/DataRef_objc.cpp" "$out"/swiftxx/*.cpp "$src/runtime_service_impl.cpp" "$src/runtime_async_impl.cpp" "$src/error_service_impl.cpp" "$src/legacy_service_impl.cpp"; do
    "${CXX:-clang++}" "${cxxflags[@]}" "$@" -c "$f" -o "$dir/$(basename "$f").o"
  done
}
build_objs "$work/objs"

# The program has a watchdog of its own. This guard kills it from outside when even the watchdog cannot run.
run_guarded() { # <command> [arguments]
  "$@" &
  local pid=$! guard status=0
  ( sleep "${RUNTIME_TIMEOUT:-300}"; echo "FAIL: the runtime test did not end in ${RUNTIME_TIMEOUT:-300} s" >&2; kill -9 "$pid" 2>/dev/null ) &
  guard=$!
  wait "$pid" || status=$?
  kill "$guard" 2>/dev/null || true
  wait "$guard" 2>/dev/null || true
  [ "$status" -eq 0 ] || exit "$status"
}

# Swift: DjinniSupportCore and DjinniSupport as static libraries, then the program. Each mode has its own build.
# RT_QUEUE_LABEL is the label of the queue that runs the blocking C++ calls of runtime.djinni.
run_mode() { # <swiftc flags> [<object folder>] [<runs>]
  local flags=$1 objs=${2:-$work/objs} mode_runs=${3:-$runs} build
  build="$work/build-$(echo "$flags" | tr -c 'a-z0-9\n' _)"
  mkdir -p "$build"
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$mods" -I "$build" -I "$spb_mod")
  echo "== [$flags]"
  # shellcheck disable=SC2086
  swiftc -emit-library -static -emit-module -emit-module-path "$build/DjinniSupportCore.swiftmodule" -module-name DjinniSupportCore \
    -parse-as-library -enable-library-evolution $flags "$repo_root"/support-lib/swift-core/*.swift -o "$build/libDjinniSupportCore.a"
  # -enable-testing lets main.swift reach the internal proxy caches with @testable import
  # shellcheck disable=SC2086
  swiftc -emit-library -static -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -enable-testing -parse-as-library $flags "${cxx[@]}" "$repo_root"/support-lib/swift/*.swift -o "$build/libDjinniSupport.a"
  local variant
  for variant in swift swift-default; do
    # shellcheck disable=SC2086
    swiftc -module-name RuntimeTest $flags "${cxx[@]}" "$out/$variant"/*.swift "$src/main.swift" "$src/error_conformance.swift" "$src/runtime_queues.swift" \
      "$objs"/*.o "$build/libDjinniSupport.a" "$build/libDjinniSupportCore.a" "$spb_mod/libSwiftProtobuf.a" -Xlinker -framework -Xlinker CoreFoundation -o "$build/runtime-test-$variant"
  done
  local i
  for i in $(seq 1 "$mode_runs"); do
    run_guarded env RT_QUEUE_LABEL=djinni.runtime.blocking "$build/runtime-test-swift"
  done
  echo "== [$flags] default queue"
  for i in $(seq 1 "$mode_runs"); do
    # Only the default queue passes the check of RT_DEFAULT_QUEUE: it has a thread for each blocking call.
    run_guarded env RT_QUEUE_LABEL=djinni.call RT_DEFAULT_QUEUE=1 "$build/runtime-test-swift-default"
  done
}
# The cxx-free variant: the generated Swift is a module of its own with library evolution, and the program imports it.
run_cxx_free() { # <swiftc flags> [<object folder>] [<runs>]
  local flags=$1 objs=${2:-$work/objs} mode_runs=${3:-$runs} build
  build="$work/build-cxx-free-$(echo "$flags" | tr -c 'a-z0-9\n' _)"
  mkdir -p "$build"
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$mods" -I "$build" -I "$spb_mod")
  echo "== [$flags] cxx-free"
  # shellcheck disable=SC2086
  swiftc -emit-library -static -emit-module -emit-module-path "$build/DjinniSupportCore.swiftmodule" -module-name DjinniSupportCore \
    -parse-as-library -enable-library-evolution $flags "$repo_root"/support-lib/swift-core/*.swift -o "$build/libDjinniSupportCore.a"
  # shellcheck disable=SC2086
  swiftc -emit-library -static -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -enable-testing -parse-as-library $flags "${cxx[@]}" "$repo_root"/support-lib/swift/*.swift -o "$build/libDjinniSupport.a"
  local variant swift_dir program
  for variant in swift swift-default; do
    swift_dir="$out_cxx_free/$variant"
    mkdir -p "$build/$variant"
    # shellcheck disable=SC2086
    # -enable-testing lets the program reach the internal marshallers, as it does in the one-module variants.
    swiftc -emit-library -static -emit-module -emit-module-path "$build/$variant/RuntimeTest.swiftmodule" -module-name RuntimeTest \
      -parse-as-library -enable-testing -enable-library-evolution $flags "${cxx[@]}" -I "$build/$variant" \
      "$swift_dir"/*.swift "$src/error_conformance.swift" -o "$build/$variant/libRuntimeTest.a"
    # The program imports the generated module, so one line goes in front of its own imports.
    program="$build/$variant/main.swift"
    { echo "@testable import RuntimeTest"; cat "$src/main.swift"; } >"$program"
    # shellcheck disable=SC2086
    swiftc -module-name RuntimeMain $flags "${cxx[@]}" -I "$build/$variant" "$program" \
      "$objs"/*.o "$build/$variant/libRuntimeTest.a" "$build/libDjinniSupport.a" "$build/libDjinniSupportCore.a" \
      "$spb_mod/libSwiftProtobuf.a" -Xlinker -framework -Xlinker CoreFoundation -o "$build/runtime-test-cxx-free-$variant"
  done
  echo "== [$flags] cxx-free blocking queue"
  local i
  for i in $(seq 1 "$mode_runs"); do
    run_guarded env RT_QUEUE_LABEL=djinni.runtime.blocking "$build/runtime-test-cxx-free-swift"
  done
  echo "== [$flags] cxx-free default queue"
  for i in $(seq 1 "$mode_runs"); do
    run_guarded env RT_QUEUE_LABEL=djinni.call RT_DEFAULT_QUEUE=1 "$build/runtime-test-cxx-free-swift-default"
  done
}

run_mode "-swift-version 5"
run_mode "-swift-version 6 -strict-concurrency=complete"
run_cxx_free "-swift-version 5"
run_cxx_free "-swift-version 6 -strict-concurrency=complete"
# The optimizer shortens object lifetimes, and it can show a lifetime bug that -Onone hides.
build_objs "$work/objs-O" -O2
run_mode "-swift-version 6 -strict-concurrency=complete -O" "$work/objs-O"
run_cxx_free "-swift-version 6 -strict-concurrency=complete -O" "$work/objs-O"
# One run is enough: ThreadSanitizer reports two accesses without an order also when they do not collide.
if [ "${RUNTIME_TSAN:-1}" = 1 ]; then
  build_objs "$work/objs-tsan" -fsanitize=thread
  TSAN_OPTIONS="halt_on_error=1 ${TSAN_OPTIONS:-}" run_mode "-swift-version 6 -strict-concurrency=complete -sanitize=thread" "$work/objs-tsan" 1
  TSAN_OPTIONS="halt_on_error=1 ${TSAN_OPTIONS:-}" run_cxx_free "-swift-version 6 -strict-concurrency=complete -sanitize=thread" "$work/objs-tsan" 1
fi
