#!/usr/bin/env bash
# Proves that a module generated with --swift-cxx-free-api keeps its public API free of C++ types.
#
# The script compiles the checked-in cxx-free test-suite cases, and it generates the whole Crux IDL with
# --swift-internal-cxx-imports and --swift-cxx-free-api. It builds the modules with library evolution and a verified
# module interface. Then clients compile without C++ interoperability and without a C++ module on the search path: one
# against the generated module, and one against the whole Crux module. The same test-suite IDL generated without the
# option cannot make a verified interface, and the script prints the diagnostic. It runs the checks for Swift 5 and for
# Swift 6 with strict concurrency checking. macOS only.
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   SWIFT_CACHE        where the SwiftProtobuf checkout and module are kept
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:?set MITTI_MOBILE_ROOT to a mitti-mobile checkout}"
domain_dir="$mitti_root/crux/djinni/domain"
extern_src="$mitti_root/crux/deps/APISchema/_generated/crux/cpp"
cache="${SWIFT_CACHE:-$HOME/.cache/djinni-swift}"
protobuf_tag=1.38.1
cases="$repo_root/test-suite/generated-src/swift-features"
client="$repo_root/ci/swift-cxx-free"
stubs="$repo_root/ci/swift-stubs"

for d in "$domain_dir" "$extern_src"; do
  [ -d "$d" ] || { echo "missing directory: $d (set MITTI_MOBILE_ROOT)" >&2; exit 2; }
done
for f in "$client/Client.swift" "$client/CruxClient.swift" "$client/ErrorConformance.swift" \
         "$client/CruxAsyncQueue.swift" "$client/CruxErrorConformance.swift" \
         "$stubs/Models.swift" "$stubs/ModelsSupport.swift"; do
  [ -f "$f" ] || { echo "missing file: $f" >&2; exit 2; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-cxx-free.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

# Generator
if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

# SwiftProtobuf is a dependency of DjinniSupport. It is built once per compiler.
spb_mod="$cache/spb-$protobuf_tag-$(swiftc --version | shasum -a 256 | cut -d' ' -f1)"
if [ ! -f "$spb_mod/SwiftProtobuf.swiftmodule" ]; then
  mkdir -p "$cache"
  # Pinned archive: a moved tag cannot change the sources
  if [ ! -d "$cache/swift-protobuf-$protobuf_tag" ]; then
    curl -fsSL --retry 3 -o "$cache/swift-protobuf-$protobuf_tag.tar.gz" "https://github.com/apple/swift-protobuf/archive/refs/tags/$protobuf_tag.tar.gz"
    [ "$(shasum -a 256 "$cache/swift-protobuf-$protobuf_tag.tar.gz" | cut -d' ' -f1)" = "7e35c119afe8f16fe4de45c2143b0f50a205db83738092336562d610469283ac" ] || { echo "SHA-256 of the SwiftProtobuf archive differs" >&2; exit 1; }
    tar -xzf "$cache/swift-protobuf-$protobuf_tag.tar.gz" -C "$cache"
  fi
  mkdir -p "$spb_mod"
  swiftc -emit-module -emit-module-path "$spb_mod/SwiftProtobuf.swiftmodule" -module-name SwiftProtobuf \
    -parse-as-library -swift-version 5 -package-name SwiftProtobuf -wmo -Onone "$cache"/swift-protobuf-$protobuf_tag/Sources/SwiftProtobuf/*.swift
fi

# Fixtures for the whole Crux IDL. The Crux IDL has no error record, so the fixture adds crux_error.
python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx" "$repo_root" main.djinni
printf 'crux_error = record {\n  message: string;\n  code: i32;\n}\n' >"$work/fx/crux/djinni/domain/ci_crux_error.djinni"
printf '@import "ci_crux_error.djinni"\n' >>"$work/fx/crux/djinni/domain/swift_fixture.djinni"

# The whole Crux IDL with the flags of the app, and with the option.
out_crux="$work/crux"
# shellcheck disable=SC2086
(cd "$work/fx" && java -jar "$jar" \
  --cpp-out "$out_crux/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h --ident-cpp-method FooBar \
  --swift-out "$out_crux/swift" --swift-module CruxBindings --swift-private-in-same-module \
  --swift-internal-cxx-imports --swift-cxx-free-api \
  --swift-sync-method crux_API.add_mutation_processor_observer \
  --swift-sync-method crux_API.add_container_status_change_observer \
  --swift-sync-method media_API.add_media_observer \
  --swiftxx-out "$out_crux/swiftxx" --swiftxx-namespace crux::generated::swift --swiftxx-include-cpp-prefix generated/ \
  --swift-error-type CruxError --swift-async-wrap com.safetyculture.crux --swift-async-queue CruxAsyncQueue.shared \
  --idl-include-path extern ${DJINNI_FLAGS:-} --idl crux/djinni/domain/swift_fixture.djinni)

# The same IDL as the cxx-free test-suite case, without the option: the negative proof.
out_negative="$work/negative"
(cd "$repo_root/test-suite" && java -jar "$jar" \
  --cpp-out "$out_negative/cpp" --cpp-namespace testsuite --ident-cpp-enum-type foo_bar \
  --swift-out "$out_negative/swift" --swift-module TestSuite --swift-private-in-same-module \
  --swift-internal-cxx-imports --swift-async-wrap djinni.testsuite --swift-error-type SwiftCxxFreeFailure \
  --swiftxx-out "$out_negative/swiftxx" --swiftxx-include-cpp-prefix "../cpp/" \
  --idl djinni/swift_cxx_free_api.djinni)

# Stub C++ modules. The glue of the case and of the negative run is the same, so one stub serves both.
mods="$work/mods"
mkdir -p "$mods"
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$mods/TestSuiteCxx.hpp" \
  "$cases/cxx-free-api/swiftxx" "$cases/cxx-free-api-future-outcome/swiftxx" "$cases/cxx-free-api-error-module/swiftxx" \
  "$cases/cxx-free-api-error-module-plain/swiftxx"
SWIFTXX_NAMESPACE=crux::generated::swift python3 "$repo_root/ci/swift_stubs.py" cxx-header "$mods/CruxBindingsCxx.hpp" "$out_crux/swiftxx"
cat >"$mods/module.modulemap" <<EOF
module DjinniSupportCxx {
  header "$repo_root/support-lib/swiftxx/djinni_support.hpp"
  header "$repo_root/support-lib/swiftxx/Future_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Data_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Outcome_swift.hpp"
  requires cplusplus
  export *
}
module TestSuiteCxx {
  header "$mods/TestSuiteCxx.hpp"
  requires cplusplus
  export *
}
module CruxBindingsCxx {
  header "$mods/CruxBindingsCxx.hpp"
  requires cplusplus
  export *
}
EOF

# S12Protos: the real s12 Swift messages of the assets protos come with the checkout; the other yamls get stubs.
python3 "$repo_root/ci/swift_stubs.py" s12protos "$work/fx/extern" "$work/S12ProtosStubs.swift" "$repo_root/ci/fixtures/s12"
cp "$repo_root"/ci/fixtures/s12/*.pb.swift "$work/"

case_files=("$cases/cxx-free-api"/swift/*.swift "$cases/cxx-free-api-future-field"/swift/*.swift
            "$cases/cxx-free-api-future-outcome"/swift/*.swift "$cases/cxx-free-api-error-module"/swift/*.swift
            "$cases/cxx-free-api-error-module-plain"/swift/*.swift)

run_mode() { # <label> <swiftc flags...>
  local tag=$1 build
  shift
  local flags="$*"
  build="$work/build-$tag"
  mkdir -p "$build" "$build/core" "$build/stubs" "$build/s12" "$build/gen" "$build/negative"
  # The clients get the directory of DjinniSupportCore only, so no C++-interop module is on their search path.
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$build/core" -I "$build/stubs" -I "$build" -I "$mods" -I "$spb_mod")
  local s12=(-parse-as-library -swift-version 5 -I "$spb_mod")

  echo "== [$tag] (a) DjinniSupportCore without C++ interop, library evolution"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/core/DjinniSupportCore.swiftmodule" \
    -emit-module-interface-path "$build/core/DjinniSupportCore.swiftinterface" -module-name DjinniSupportCore \
    -parse-as-library -enable-library-evolution -emit-module-interface -verify-emitted-module-interface \
    $flags "$repo_root"/support-lib/swift-core/*.swift
  echo "== [$tag] (b) DjinniSupport with C++ interop"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -parse-as-library $flags "${cxx[@]}" "$repo_root"/support-lib/swift/*.swift
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/s12/S12Protos.swiftmodule" -module-name S12Protos \
    "${s12[@]}" "$work/S12ProtosStubs.swift" "$work"/*.pb.swift
  # The two modules of the extern record of the future-outcome case. The type module keeps library evolution, so the
  # generated module imports it without a warning.
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/stubs/Models.swiftmodule" \
    -emit-module-interface-path "$build/stubs/Models.swiftinterface" -module-name Models \
    -parse-as-library -enable-library-evolution -emit-module-interface -verify-emitted-module-interface \
    $flags "$stubs/Models.swift"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/stubs/ModelsSupport.swiftmodule" -module-name ModelsSupport \
    -parse-as-library $flags "${cxx[@]}" "$stubs/ModelsSupport.swift"

  echo "== [$tag] (c) the cxx-free-api module: library evolution, verified interface, no warning"
  local module_log="$build/gen/module.log"
  # shellcheck disable=SC2086
  if ! swiftc -emit-module -emit-module-path "$build/gen/TestSuite.swiftmodule" \
      -emit-module-interface-path "$build/gen/TestSuite.swiftinterface" -module-name TestSuite -parse-as-library \
      -enable-library-evolution -emit-module-interface -verify-emitted-module-interface \
      $flags "${cxx[@]}" "${case_files[@]}" "$client/ErrorConformance.swift" \
      "$client/ModelsErrorConformance.swift" >"$module_log" 2>&1; then
    echo "FAIL: the cxx-free-api module did not build:" >&2
    cat "$module_log" >&2
    exit 1
  fi
  if grep -q "warning:" "$module_log"; then
    echo "FAIL: the cxx-free-api module has warnings:" >&2
    cat "$module_log" >&2
    exit 1
  fi
  if grep -qE "^import (DjinniSupport|DjinniSupportCxx|TestSuiteCxx)\$" "$build/gen/TestSuite.swiftinterface"; then
    echo "FAIL: the interface of the cxx-free-api module imports a C++ module:" >&2
    grep -nE "^import " "$build/gen/TestSuite.swiftinterface" >&2
    exit 1
  fi
  echo "CXX-FREE MODULE OK [$tag]"

  echo "== [$tag] (d) the whole Crux IDL with the app flags: library evolution, verified interface"
  local crux_log="$build/gen/crux.log"
  # shellcheck disable=SC2086
  if ! swiftc -emit-module -emit-module-path "$build/gen/CruxBindings.swiftmodule" \
      -emit-module-interface-path "$build/gen/CruxBindings.swiftinterface" -module-name CruxBindings -parse-as-library \
      -enable-library-evolution -emit-module-interface -verify-emitted-module-interface \
      $flags "${cxx[@]}" -I "$build/s12" "$out_crux"/swift/*.swift \
      "$client/CruxAsyncQueue.swift" "$client/CruxErrorConformance.swift" >"$crux_log" 2>&1; then
    echo "FAIL: the Crux module did not build:" >&2
    cat "$crux_log" >&2
    exit 1
  fi
  if grep -qE "^import (DjinniSupport|DjinniSupportCxx|CruxBindingsCxx)\$" "$build/gen/CruxBindings.swiftinterface"; then
    echo "FAIL: the interface of the Crux module imports a C++ module:" >&2
    grep -nE "^import " "$build/gen/CruxBindings.swiftinterface" >&2
    exit 1
  fi
  if ! grep -qx "import S12Protos" "$build/gen/CruxBindings.swiftinterface"; then
    echo "FAIL: the interface of the Crux module does not import S12Protos for its message types." >&2
    exit 1
  fi
  # The stub S12Protos is not resilient. Its library-evolution warning is the only warning the module may print; each
  # diagnostic is printed twice, when the module is emitted and when its interface is verified.
  local warnings resilient
  warnings=$(grep -cE "^[^ |].*warning: " "$crux_log" || true)
  resilient=$(grep -cE "^[^ |].*warning: module 'S12Protos' was not compiled with library evolution support" "$crux_log" || true)
  if [ "$warnings" -ne "$resilient" ]; then
    echo "FAIL: the Crux module has a warning that is not the library-evolution warning of S12Protos:" >&2
    grep -E "^[^ |].*warning: " "$crux_log" | grep -vF "warning: module 'S12Protos' was not compiled with library evolution support" | head -5 >&2
    exit 1
  fi
  echo "CXX-FREE CRUX MODULE OK [$tag] ($((warnings / 2)) diagnostics, each printed twice ($warnings lines); all are the S12Protos library-evolution warning)"

  echo "== [$tag] (e) the client without C++ interop"
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name CxxFreeClient $flags -I "$build/gen" -I "$build/core" -I "$build/stubs" -I "$build/s12" -I "$spb_mod" \
    "$client/Client.swift"
  echo "CXX-FREE CLIENT OK [$tag]"

  echo "== [$tag] (e2) the same client against the interface of the generated module, in an empty directory"
  local only="$build/interface-only"
  mkdir -p "$only"
  cp "$build/gen/TestSuite.swiftinterface" "$only/"
  cp "$build/core"/DjinniSupportCore.swiftinterface "$build/core"/DjinniSupportCore.swiftmodule "$only/"
  cp "$build/stubs"/Models.swiftinterface "$build/stubs"/Models.swiftmodule "$only/"
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name CxxFreeClient $flags -I "$only" "$client/Client.swift"
  echo "CXX-FREE INTERFACE CLIENT OK [$tag]"

  echo "== [$tag] (e3) the Crux client without C++ interop"
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name CruxClient $flags -I "$build/gen" -I "$build/core" -I "$build/s12" -I "$spb_mod" \
    "$client/CruxClient.swift"
  echo "CXX-FREE CRUX CLIENT OK [$tag]"

  echo "== [$tag] (f) the same test-suite IDL without --swift-cxx-free-api must not make a verified interface"
  local negative="$build/negative" negative_log="$build/negative/module.log"
  # shellcheck disable=SC2086
  if swiftc -emit-module -emit-module-path "$negative/TestSuite.swiftmodule" \
      -emit-module-interface-path "$negative/TestSuite.swiftinterface" -module-name TestSuite -parse-as-library \
      -enable-library-evolution -emit-module-interface -verify-emitted-module-interface \
      $flags "${cxx[@]}" "$out_negative"/swift/*.swift "$client/ErrorConformance.swift" >"$negative_log" 2>&1; then
    echo "FAIL: the module without --swift-cxx-free-api made a verified interface." >&2
    exit 1
  fi
  # The interface names the C++ namespace through the clang module. Swift 6.3 prints it without the member.
  if ! grep -qF "cannot find type '__ObjC" "$negative_log"; then
    echo "FAIL: the module without the option failed for another reason:" >&2
    cat "$negative_log" >&2
    exit 1
  fi
  echo "  interface: $(grep -m1 "cannot find type '__ObjC" "$negative_log")"
  echo "CXX-FREE NEGATIVE REJECTED [$tag]"
}

run_mode swift5 -swift-version 5
run_mode swift6 -swift-version 6 -strict-concurrency=complete
