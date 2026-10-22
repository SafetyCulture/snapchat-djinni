#!/usr/bin/env bash
# Typechecks the generated Swift for the Crux assets IDL against support-lib/swift and
# syntax-checks the generated Swift/C++ glue.
#
# The script generates Swift and Swift/C++ glue with the built generator. It runs
# `swiftc -typecheck` over the generated Swift in Swift 5 mode and in Swift 6 mode with complete
# strict concurrency checking. Then it compiles the glue with `-fsyntax-only`. SwiftProtobuf is the real library. The
# generated protobuf types (module S12Protos) and the generated Swift/C++ declarations
# (module CruxCxx), the protobuf C++ headers and the message translators are stubs,
# because they come from other build steps.
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   IDL_FILES          comma separated files of crux/djinni/domain to import
#                      (default: common.djinni,media.djinni,assets.djinni)
#   DJINNI_FLAGS       extra generator flags
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   SWIFT_CACHE        where the SwiftProtobuf checkout and module are kept
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:-$HOME/Desktop/safetyculture/mitti-mobile}"
domain_dir="$mitti_root/crux/djinni/domain"
extern_src="$mitti_root/crux/deps/APISchema/_generated/crux/cpp"
idl_files="${IDL_FILES:-common.djinni,media.djinni,assets.djinni}"
cache="${SWIFT_CACHE:-$HOME/.cache/djinni-swift}"
protobuf_tag=1.28.2

for d in "$domain_dir" "$extern_src"; do
  [ -d "$d" ] || { echo "missing directory: $d (set MITTI_MOBILE_ROOT)" >&2; exit 2; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-swift.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

# Generator
if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

# SwiftProtobuf, built once per compiler.
spb_mod="$cache/spb-$protobuf_tag-$(swiftc --version | shasum -a 256 | cut -d' ' -f1)"
if [ ! -f "$spb_mod/SwiftProtobuf.swiftmodule" ]; then
  mkdir -p "$cache"
  [ -d "$cache/swift-protobuf" ] || git clone --quiet --depth 1 --branch "$protobuf_tag" https://github.com/apple/swift-protobuf "$cache/swift-protobuf"
  mkdir -p "$spb_mod"
  swiftc -emit-module -emit-module-path "$spb_mod/SwiftProtobuf.swiftmodule" -module-name SwiftProtobuf \
    -parse-as-library -swift-version 5 -wmo -Onone "$cache"/swift-protobuf/Sources/SwiftProtobuf/*.swift
fi

# Fixtures and generation
python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx" "$repo_root" "$idl_files"
out="$work/out"
# shellcheck disable=SC2086
(cd "$work/fx" && java -jar "$jar" \
  --cpp-out "$out/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h --ident-cpp-method FooBar \
  --swift-out "$out/swift" --swift-module Crux --swift-private-in-same-module \
  --swiftxx-out "$out/swiftxx" --swiftxx-include-cpp-prefix generated/ \
  --idl-include-path extern ${DJINNI_FLAGS:-} --idl crux/djinni/domain/swift_fixture.djinni)
# The same IDL with the async wrappers.
out_async="$work/out-async"
# shellcheck disable=SC2086
(cd "$work/fx" && java -jar "$jar" \
  --cpp-out "$out_async/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h --ident-cpp-method FooBar \
  --swift-out "$out_async/swift" --swift-module Crux --swift-private-in-same-module \
  --swift-async-wrap com.safetyculture.crux \
  --idl-include-path extern ${DJINNI_FLAGS:-} --idl crux/djinni/domain/swift_fixture.djinni)

# Stub modules
mods="$work/mods"
mkdir -p "$mods"
python3 "$repo_root/ci/swift_stubs.py" s12protos "$work/fx/extern" "$work/S12Protos.swift"
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$mods/CruxCxx.hpp" "$out/swiftxx"

# Test-suite cases: the host interface triple, the keyword identifiers, the built-in types and the
# Sendable cases. The generated files are the checked-in expected outputs of test-suite/run_djinni.sh.
cases="$repo_root/test-suite/generated-src/swift-features"
case_names=(host idents types sendable legacy future-field async)
tsmods="$work/ts-mods"
mkdir -p "$tsmods"
swiftxx_dirs=()
for c in "${case_names[@]}"; do swiftxx_dirs+=("$cases/$c/swiftxx"); done
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$tsmods/TestSuiteCxx.hpp" "${swiftxx_dirs[@]}"

support_module() {
  cat <<EOF
module DjinniSupportCxx {
  header "$repo_root/support-lib/swiftxx/djinni_support.hpp"
  header "$repo_root/support-lib/swiftxx/Future_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Data_swift.hpp"
  header "$repo_root/support-lib/swiftxx/Outcome_swift.hpp"
  requires cplusplus
  export *
}
EOF
}
{ support_module; printf 'module CruxCxx {\n  header "%s/CruxCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$mods"; } >"$mods/module.modulemap"
{ support_module; printf 'module TestSuiteCxx {\n  header "%s/TestSuiteCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$tsmods"; } >"$tsmods/module.modulemap"

# One pass compiles DjinniSupport and typechecks the generated Swift with the given swiftc flags.
swift_pass() { # <swiftc flags>
  local flags=$1 build
  build="$work/build-$(echo "$flags" | tr -c 'a-z0-9\n' _)"
  mkdir -p "$build"
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$build" -I "$spb_mod")
  swiftc -emit-module -emit-module-path "$build/S12Protos.swiftmodule" -module-name S12Protos \
    -parse-as-library -swift-version 5 -I "$spb_mod" "$work/S12Protos.swift"
  echo "== [$flags] DjinniSupport (support-lib/swift)"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -parse-as-library $flags "${cxx[@]}" -I "$mods" "$repo_root"/support-lib/swift/*.swift
  echo "== [$flags] Crux (generated Swift, $(ls "$out"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name Crux $flags "${cxx[@]}" -I "$mods" "$out"/swift/*.swift
  echo "SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] Crux with --swift-async-wrap (generated Swift, $(ls "$out_async"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name Crux $flags "${cxx[@]}" -I "$mods" "$out_async"/swift/*.swift
  echo "SWIFT ASYNC TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite (checked-in Swift cases)"
  local files=()
  for c in "${case_names[@]}"; do files+=("$cases/$c"/swift/*.swift); done
  # shellcheck disable=SC2086
  swiftc -typecheck -module-name TestSuite $flags "${cxx[@]}" -I "$tsmods" "${files[@]}"
  echo "TEST-SUITE SWIFT TYPECHECK OK [$flags]"
}
swift_pass "-swift-version 5"
swift_pass "-swift-version 6 -strict-concurrency=complete"

echo "== C++ glue ($(ls "$out"/swiftxx/*.cc | wc -l | tr -d ' ') files): ${CXX:-clang++} -std=c++20 -fsyntax-only"
python3 "$repo_root/ci/swift_stubs.py" cxx-stubs "$work/fx/extern" "$work/cxxstubs"
ls "$out"/swiftxx/*.cc | xargs -P 4 -I{} "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
  -I "$out/cpp" -I "$out/cpp/generated" -I "$work/cxxstubs" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" {}
echo "C++ GLUE SYNTAX OK"

for c in "${case_names[@]}"; do
  for f in "$cases/$c"/swiftxx/*.cpp; do
    [ -e "$f" ] || continue
    "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
      -I "$cases/$c/cpp" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" "$f"
  done
done
echo "TEST-SUITE C++ GLUE SYNTAX OK"

echo "== Runtime C++ (support-lib/swiftxx, objc/DataRef_objc.cpp): clang++ -fsyntax-only"
for f in "$repo_root"/support-lib/swiftxx/*.cpp "$repo_root/support-lib/objc/DataRef_objc.cpp"; do
  "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations -DDATAREF_OBJC=1 \
    -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" "$f"
done
echo "RUNTIME C++ SYNTAX OK"
