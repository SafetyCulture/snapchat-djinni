#!/usr/bin/env bash
# Typechecks the generated Swift for the Crux assets IDL against support-lib/swift-core and
# support-lib/swift and syntax-checks the generated Swift/C++ glue.
#
# The script generates Swift and Swift/C++ glue with the built generator. It compiles the generated Swift to SIL
# (`swiftc -emit-sil`) in three modes: Swift 5, Swift 6 with strict concurrency checking set to complete, and Swift 6
# with NonisolatedNonsendingByDefault (the mode of Approachable Concurrency in the app modules). The data-race checks
# of Swift 6 run on SIL, after the type checker, so `-typecheck` is not enough. Then the script compiles the glue with
# `-fsyntax-only`. SwiftProtobuf is the real library. The
# generated protobuf types (module S12Protos) are the real messages of the assets protos
# (ci/fixtures/s12) plus stubs for the other yamls; the generated Swift/C++ declarations
# (module CruxCxx), the protobuf C++ headers and the message translators are stubs,
# because they come from other build steps. One more pass generates the whole Crux IDL (main.djinni) with
# --swift-error-type CruxError, --swift-async-wrap and three --swift-sync-method values; the fixture adds the
# crux_error record, which Crux lacks.
#
# It also compiles the Java, JNI C++ and Objective-C++ output of the +sw host case of the test suite, so the
# other languages still compile next to the Swift files. That needs javac and the JNI headers of a JDK.
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   JAVA_HOME          JDK with include/jni.h (default: derived from javac)
#   IDL_FILES          comma separated files of crux/djinni/domain to import
#                      (default: common.djinni,media.djinni,assets.djinni)
#   DJINNI_FLAGS       extra generator flags
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   SWIFT_CACHE        where the SwiftProtobuf checkout and module are kept
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:?set MITTI_MOBILE_ROOT to a mitti-mobile checkout}"
domain_dir="$mitti_root/crux/djinni/domain"
extern_src="$mitti_root/crux/deps/APISchema/_generated/crux/cpp"
idl_files="${IDL_FILES:-common.djinni,media.djinni,assets.djinni}"
cache="${SWIFT_CACHE:-$HOME/.cache/djinni-swift}"
protobuf_tag=1.38.1

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
# The whole Crux IDL with --swift-error-type and the async wrappers. The Crux IDL has no error record, so the
# fixture adds crux_error. Three registration methods get the synchronous form of --swift-sync-method.
python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx-error" "$repo_root" main.djinni
printf 'crux_error = record {\n  message: string;\n  code: i32;\n}\n' >"$work/fx-error/crux/djinni/domain/ci_crux_error.djinni"
printf '@import "ci_crux_error.djinni"\n' >>"$work/fx-error/crux/djinni/domain/swift_fixture.djinni"
# The same fixture with --swift-internal-cxx-imports. The consumer turns the option on, so the public signatures of
# the whole IDL must stay valid when the C++ glue imports are internal.
out_error_internal="$work/out-error-internal"
# shellcheck disable=SC2086
(cd "$work/fx-error" && java -jar "$jar" \
  --swift-out "$out_error_internal/swift" --swift-module Crux --swift-private-in-same-module \
  --swift-async-wrap com.safetyculture.crux --swift-error-type CruxError --swift-internal-cxx-imports \
  --idl-include-path extern ${DJINNI_FLAGS:-} --idl crux/djinni/domain/swift_fixture.djinni)
out_error="$work/out-error"
# shellcheck disable=SC2086
(cd "$work/fx-error" && java -jar "$jar" \
  --cpp-out "$out_error/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h --ident-cpp-method FooBar \
  --swift-out "$out_error/swift" --swift-module Crux --swift-private-in-same-module \
  --swiftxx-out "$out_error/swiftxx" --swiftxx-include-cpp-prefix generated/ \
  --swift-async-wrap com.safetyculture.crux --swift-error-type CruxError \
  --swift-sync-method crux_API.add_mutation_processor_observer \
  --swift-sync-method crux_API.add_container_status_change_observer \
  --swift-sync-method media_API.add_media_observer \
  --idl-include-path extern ${DJINNI_FLAGS:-} --idl crux/djinni/domain/swift_fixture.djinni)

# Stub modules
mods="$work/mods"
mkdir -p "$mods"
python3 "$repo_root/ci/swift_stubs.py" s12protos "$work/fx/extern" "$work/S12ProtosStubs.swift" "$repo_root/ci/fixtures/s12"
# The real s12 Swift messages of the assets protos come with the checkout; the other yamls keep stubs
cp "$repo_root"/ci/fixtures/s12/*.pb.swift "$work/"
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$mods/CruxCxx.hpp" "$out/swiftxx"
errmods="$work/error-mods"
mkdir -p "$errmods"
python3 "$repo_root/ci/swift_stubs.py" s12protos "$work/fx-error/extern" "$work/S12ProtosErrorStubs.swift" "$repo_root/ci/fixtures/s12"
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$errmods/CruxCxx.hpp" "$out_error/swiftxx"

# Test-suite cases: the checked-in expected outputs of test-suite/run_djinni.sh.
cases="$repo_root/test-suite/generated-src/swift-features"
case_names=(host idents types sendable legacy future-field async error result-name naming deriving const-strings labels recursive)
tsmods="$work/ts-mods"
mkdir -p "$tsmods"
swiftxx_dirs=()
for c in "${case_names[@]}"; do swiftxx_dirs+=("$cases/$c/swiftxx"); done
python3 "$repo_root/ci/swift_stubs.py" cxx-header "$tsmods/TestSuiteCxx.hpp" "${swiftxx_dirs[@]}"

# The case with non-default --swiftxx-* flags has its own stub modules. Its base library module is
# OptionsSupport, which re-exports the support headers, and its glue namespace is djinni_options.
optmods="$work/opt-mods"
mkdir -p "$optmods"
SWIFTXX_NAMESPACE=djinni_options python3 "$repo_root/ci/swift_stubs.py" cxx-header "$optmods/TestSuiteCxx.hpp" "$cases/options/swiftxx"
printf '#pragma once\n#include "djinni_support.hpp"\n' >"$optmods/OptionsSupport.hpp"

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
{ support_module; printf 'module CruxCxx {\n  header "%s/CruxCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$errmods"; } >"$errmods/module.modulemap"
{ support_module; printf 'module TestSuiteCxx {\n  header "%s/TestSuiteCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$tsmods"; } >"$tsmods/module.modulemap"
{
  support_module
  printf 'module OptionsSupport {\n  header "%s/OptionsSupport.hpp"\n  requires cplusplus\n  export *\n}\n' "$optmods"
  printf 'module TestSuiteCxx {\n  header "%s/TestSuiteCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$optmods"
} >"$optmods/module.modulemap"

# Cases with the same type names as another case have their own stub modules.
single_case_mods() { # <module dir> <case>
  mkdir -p "$1"
  python3 "$repo_root/ci/swift_stubs.py" cxx-header "$1/TestSuiteCxx.hpp" "$cases/$2/swiftxx"
  { support_module; printf 'module TestSuiteCxx {\n  header "%s/TestSuiteCxx.hpp"\n  requires cplusplus\n  export *\n}\n' "$1"; } >"$1/module.modulemap"
}
single_case_mods "$work/error-legacy-mods" error-legacy
single_case_mods "$work/separate-mods" separate-module
# A plain import next to an explicit level is an error, so the internal-imports case has its own module.
single_case_mods "$work/internal-imports-single-mods" internal-imports
single_case_mods "$work/internal-imports-mods" internal-imports-separate
single_case_mods "$work/sync-listener-mods" sync-listener
single_case_mods "$work/sync-listener-error-mods" sync-listener-error
single_case_mods "$work/sync-doc-mods" sync-doc
# The cxx-free cases have their own module, because they write an access level on every import.
single_case_mods "$work/cxx-free-mods" cxx-free-api
single_case_mods "$work/cxx-free-outcome-mods" cxx-free-api-future-outcome
single_case_mods "$work/cxx-free-error-mods" cxx-free-api-error-module
single_case_mods "$work/cxx-free-error-plain-mods" cxx-free-api-error-module-plain
# The case with a nested glue namespace (--swiftxx-namespace djinni_options::nested) has its own stub module.
SWIFTXX_NAMESPACE='djinni_options::nested' single_case_mods "$work/nested-mods" nested-ns

# The application declares how its error type holds a C++ exception, so the stub stands in for it.
error_conformance="$work/CruxErrorConformance.swift"
cat >"$error_conformance" <<'EOF'
import DjinniSupport

extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
EOF

# The data-race checks of Swift 6 run on SIL, after the type checker.
swift_check() { # <swiftc arguments>
  swiftc -emit-sil -wmo -parse-as-library -o /dev/null "$@"
}
# One pass compiles DjinniSupport and compiles the generated Swift to SIL with the given swiftc flags.
swift_pass() { # <swiftc flags>
  local flags=$1 build
  build="$work/build-$(echo "$flags" | tr -c 'a-z0-9\n' _)"
  mkdir -p "$build"
  local cxx=(-cxx-interoperability-mode=default -Xcc -std=c++20 -Xcc -Wno-deprecated-declarations -Xcc "-I$repo_root/support-lib/swiftxx" -I "$build" -I "$spb_mod")
  swiftc -emit-module -emit-module-path "$build/S12Protos.swiftmodule" -module-name S12Protos \
    -parse-as-library -swift-version 5 -I "$spb_mod" "$work/S12ProtosStubs.swift" "$work"/*.pb.swift
  # DjinniSupport is a package with its own settings; only the modules that use the generated code turn the
  # upcoming feature on, so its nonisolated members stay concurrent.
  local support_flags=${flags/ -enable-upcoming-feature NonisolatedNonsendingByDefault/}
  echo "== [$flags] DjinniSupportCore (support-lib/swift-core, $support_flags)"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/DjinniSupportCore.swiftmodule" -module-name DjinniSupportCore \
    -parse-as-library -enable-library-evolution $support_flags "$repo_root"/support-lib/swift-core/*.swift
  echo "== [$flags] DjinniSupport (support-lib/swift, $support_flags)"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/DjinniSupport.swiftmodule" -module-name DjinniSupport \
    -parse-as-library $support_flags "${cxx[@]}" -I "$mods" "$repo_root"/support-lib/swift/*.swift
  # The closure of Future.getResult runs on a global queue. Strict concurrency must reject a main-actor closure there.
  case "$flags" in
    *strict-concurrency*)
      echo "== [$flags] negative case: a main-actor closure in Future.getResult"
      # shellcheck disable=SC2086
      if negative="$(swiftc -typecheck -parse-as-library -module-name Negative $flags "${cxx[@]}" -I "$mods" "$repo_root/ci/swift-negative/future_get_result_main_actor.swift" 2>&1)"; then
        echo "FAIL: the main-actor closure typechecks, so Future.getResult is not @Sendable" >&2
        exit 1
      fi
      printf '%s\n' "$negative" | grep -q "main actor-isolated" || { echo "FAIL: the negative case failed for another reason:" >&2; printf '%s\n' "$negative" >&2; exit 1; }
      echo "NEGATIVE CASE REJECTED [$flags]"
      ;;
  esac
  echo "== [$flags] Crux (generated Swift, $(ls "$out"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swift_check -module-name Crux $flags "${cxx[@]}" -I "$mods" "$out"/swift/*.swift
  echo "SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] Crux with --swift-async-wrap (generated Swift, $(ls "$out_async"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swift_check -module-name Crux $flags "${cxx[@]}" -I "$mods" "$out_async"/swift/*.swift
  echo "SWIFT ASYNC TYPECHECK OK [$flags]"
  # The S12Protos module of the whole Crux IDL has more messages, so it has its own directory.
  mkdir -p "$build/error"
  cp "$build"/DjinniSupport.* "$build"/DjinniSupportCore.* "$build/error/"
  swiftc -emit-module -emit-module-path "$build/error/S12Protos.swiftmodule" -module-name S12Protos \
    -parse-as-library -swift-version 5 -I "$spb_mod" "$work/S12ProtosErrorStubs.swift" "$work"/*.pb.swift
  local errcxx=("${cxx[@]/#$build/$build/error}")
  echo "== [$flags] Crux IDL with --swift-error-type, --swift-async-wrap and --swift-sync-method (generated Swift, $(ls "$out_error"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swift_check -module-name Crux $flags "${errcxx[@]}" -I "$errmods" "$out_error"/swift/*.swift "$error_conformance"
  echo "SWIFT ERROR TYPE TYPECHECK OK [$flags]"
  echo "== [$flags] Crux IDL with --swift-internal-cxx-imports (generated Swift, $(ls "$out_error_internal"/swift/*.swift | wc -l | tr -d ' ') files)"
  # shellcheck disable=SC2086
  swift_check -module-name Crux $flags "${errcxx[@]}" -I "$errmods" "$out_error_internal"/swift/*.swift "$error_conformance"
  echo "SWIFT INTERNAL-IMPORTS TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite (checked-in Swift cases)"
  local files=()
  for c in "${case_names[@]}"; do files+=("$cases/$c"/swift/*.swift); done
  files+=("$error_conformance" "$repo_root/ci/swift-typecheck/AsyncCallers.swift")
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$tsmods" "${files[@]}"
  echo "TEST-SUITE SWIFT TYPECHECK OK [$flags]"
  # This file shares a value that is not Sendable. It must fail, or the data-race checks did not run.
  case "$flags" in
    *swift-version\ 6*)
      echo "== [$flags] negative case: two tasks share the NSData of a wrapper method"
      # shellcheck disable=SC2086
      if negative="$(swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$tsmods" "${files[@]}" "$repo_root/ci/swift-negative/share_wrapper_result.swift" 2>&1)"; then
        echo "FAIL: two tasks share a value that is not Sendable, and the SIL check accepts it" >&2
        exit 1
      fi
      printf '%s\n' "$negative" | grep -q "risks causing data races" || { echo "FAIL: the data-race negative case failed for another reason:" >&2; printf '%s\n' "$negative" >&2; exit 1; }
      echo "NEGATIVE DATA-RACE CASE REJECTED [$flags]"
      ;;
  esac
  echo "== [$flags] TestSuite options (--swiftxx-namespace, --swiftxx-include-prefix, --swiftxx-base-lib-*)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$optmods" "$cases/options"/swift/*.swift
  echo "TEST-SUITE OPTIONS SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite error-legacy (--swift-error-type, --swift-legacy-records, --swift-async-wrap)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/error-legacy-mods" "$cases/error-legacy"/swift/*.swift "$error_conformance"
  echo "TEST-SUITE ERROR-LEGACY SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite nested-ns (--swiftxx-namespace djinni_options::nested)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/nested-mods" "$cases/nested-ns"/swift/*.swift
  echo "TEST-SUITE NESTED-NS SWIFT TYPECHECK OK [$flags]"
  # Without --swift-private-in-same-module the public files and the private files are two modules.
  echo "== [$flags] TestSuite separate-module"
  local sm="$build/separate" public=() private=() f
  mkdir -p "$sm"
  for f in "$cases/separate-module"/swift/*.swift; do
    case "$f" in *+Private.swift) private+=("$f") ;; *) public+=("$f") ;; esac
  done
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$sm/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/separate-mods" "${public[@]}"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuitePrivate $flags "${cxx[@]}" -I "$work/separate-mods" -I "$sm" "${private[@]}"
  echo "TEST-SUITE SEPARATE-MODULE SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite internal-imports (--swift-internal-cxx-imports)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/internal-imports-single-mods" "$cases/internal-imports"/swift/*.swift
  echo "TEST-SUITE INTERNAL-IMPORTS SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite cxx-free-api (--swift-internal-cxx-imports, --swift-cxx-free-api)"
  local cf="$build/cxx-free"
  mkdir -p "$cf"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$cf/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/cxx-free-mods" "$cases/cxx-free-api"/swift/*.swift \
    "$cases/cxx-free-api-future-field"/swift/*.swift "$repo_root/ci/swift-cxx-free/ErrorConformance.swift"
  echo "TEST-SUITE CXX-FREE-API SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite cxx-free-api-future-outcome (future<outcome<T, E>> of an extern module)"
  # The extern Swift type and its marshaller are two modules: the public API names the type only.
  mkdir -p "$build/stubs"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/stubs/Models.swiftmodule" -module-name Models \
    -parse-as-library -enable-library-evolution $flags "$repo_root/ci/swift-stubs/Models.swift"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$build/stubs/ModelsSupport.swiftmodule" -module-name ModelsSupport \
    -parse-as-library $flags "${cxx[@]}" -I "$mods" -I "$build/stubs" "$repo_root/ci/swift-stubs/ModelsSupport.swift"
  local co="$build/cxx-free-outcome"
  mkdir -p "$co"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$co/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/cxx-free-outcome-mods" -I "$build/stubs" "$cases/cxx-free-api-future-outcome"/swift/*.swift
  echo "TEST-SUITE CXX-FREE-FUTURE-OUTCOME SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite cxx-free-api-error-module (--swift-error-type of an extern record)"
  local ce="$build/cxx-free-error"
  mkdir -p "$ce"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$ce/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/cxx-free-error-mods" -I "$build/stubs" "$cases/cxx-free-api-error-module"/swift/*.swift \
    "$repo_root/ci/swift-cxx-free/ModelsErrorConformance.swift"
  echo "TEST-SUITE CXX-FREE-ERROR-MODULE SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite cxx-free-api-error-module-plain (no async wrapper)"
  local cp="$build/cxx-free-error-plain"
  mkdir -p "$cp"
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$cp/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/cxx-free-error-plain-mods" -I "$build/stubs" "$cases/cxx-free-api-error-module-plain"/swift/*.swift \
    "$repo_root/ci/swift-cxx-free/ModelsErrorConformance.swift"
  echo "TEST-SUITE CXX-FREE-ERROR-MODULE-PLAIN SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite internal-imports-separate (--swift-internal-cxx-imports)"
  local im="$build/internal-imports" ipublic=() iprivate=()
  mkdir -p "$im"
  for f in "$cases/internal-imports-separate"/swift/*.swift; do
    case "$f" in *+Private.swift) iprivate+=("$f") ;; *) ipublic+=("$f") ;; esac
  done
  # shellcheck disable=SC2086
  swiftc -emit-module -emit-module-path "$im/TestSuite.swiftmodule" -module-name TestSuite -parse-as-library \
    $flags "${cxx[@]}" -I "$work/internal-imports-mods" "${ipublic[@]}"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuitePrivate $flags "${cxx[@]}" -I "$work/internal-imports-mods" -I "$im" "${iprivate[@]}"
  echo "TEST-SUITE INTERNAL-IMPORTS-SEPARATE SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite sync-listener (--swift-sync-method)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/sync-listener-mods" "$cases/sync-listener"/swift/*.swift
  echo "TEST-SUITE SYNC-LISTENER SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite sync-listener-error (--swift-sync-method, --swift-error-type)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/sync-listener-error-mods" "$cases/sync-listener-error"/swift/*.swift "$error_conformance"
  echo "TEST-SUITE SYNC-LISTENER-ERROR SWIFT TYPECHECK OK [$flags]"
  echo "== [$flags] TestSuite sync-doc (a keyword parameter of a synchronous form)"
  # shellcheck disable=SC2086
  swift_check -module-name TestSuite $flags "${cxx[@]}" -I "$work/sync-doc-mods" "$cases/sync-doc"/swift/*.swift
  echo "TEST-SUITE SYNC-DOC SWIFT TYPECHECK OK [$flags]"
}
swift_pass "-swift-version 5"
swift_pass "-swift-version 6 -strict-concurrency=complete"
swift_pass "-swift-version 6 -strict-concurrency=complete -enable-upcoming-feature NonisolatedNonsendingByDefault"

# The Swift runtime never aborts the process: no try!, fatalError, as!, or force unwrap
if grep -nE 'try!|fatalError|as!|[]A-Za-z0-9_)]!([^=]|$)' "$repo_root"/support-lib/swift/*.swift "$repo_root"/support-lib/swift-core/*.swift; then
  echo "FAIL: a crash construct in support-lib/swift or support-lib/swift-core" >&2
  exit 1
fi
echo "NO CRASH CONSTRUCTS OK"

echo "== C++ glue ($(ls "$out"/swiftxx/*.cc | wc -l | tr -d ' ') files): ${CXX:-clang++} -std=c++20 -fsyntax-only"
python3 "$repo_root/ci/swift_stubs.py" cxx-stubs "$work/fx/extern" "$work/cxxstubs"
ls "$out"/swiftxx/*.cc | xargs -P 4 -I{} "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
  -I "$out/cpp" -I "$out/cpp/generated" -I "$work/cxxstubs" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" {}
echo "C++ GLUE SYNTAX OK"

for c in "${case_names[@]}"; do
  for f in "$cases/$c"/swiftxx/*.cpp; do
    [ -e "$f" ] || continue
    "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
      -I "$cases/$c/cpp" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" "$f"
  done
done
echo "TEST-SUITE C++ GLUE SYNTAX OK"

# Each include prefix of the options case is a directory on the include path.
inc="$work/options-inc"
mkdir -p "$inc"
cp -R "$cases/options/swiftxx" "$inc/options"
cp -R "$cases/options/cpp" "$inc/cpp"
cp -R "$repo_root/support-lib/swiftxx" "$inc/support"
for f in "$inc"/options/*.cpp; do
  "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
    -I "$inc" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib" "$f"
done
echo "TEST-SUITE OPTIONS C++ GLUE SYNTAX OK"

# The cxx-free future-outcome and error-module cases and sync-doc are not in this list: their glue includes the header
# of an extern translator, which this check does not stub, or a parameter named for.
for c in error-legacy separate-module nested-ns internal-imports internal-imports-separate sync-listener sync-listener-error cxx-free-api; do
  for f in "$cases/$c"/swiftxx/*.cpp; do
    "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations \
      -I "$cases/$c/cpp" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" "$f"
  done
done
echo "TEST-SUITE ERROR-LEGACY, SEPARATE-MODULE, NESTED-NS, INTERNAL-IMPORTS, INTERNAL-IMPORTS-SEPARATE, SYNC-LISTENER, SYNC-LISTENER-ERROR AND CXX-FREE-API C++ GLUE SYNTAX OK"

# An interface with +o +j +sw gets host proxies in Java, JNI C++ and Objective-C++ next to the Swift proxy.
# The other languages must still compile next to the Swift files.
host="$cases/host"
echo "== Host languages of the +sw interfaces (swift-features/host): javac, JNI C++, Objective-C++"
java_home="${JAVA_HOME:-}"
[ -n "$java_home" ] || java_home="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
[ -f "$java_home/include/jni.h" ] || { echo "jni.h is not in $java_home/include (set JAVA_HOME)" >&2; exit 2; }
mkdir -p "$work/host-java"
# shellcheck disable=SC2046
javac -nowarn -d "$work/host-java" $(find "$host/java" "$repo_root/support-lib/java" -name '*.java')
echo "HOST JAVA OK"
for f in "$host"/jni/*.cpp; do
  "${CXX:-clang++}" -std=c++17 -fsyntax-only -I "$host/jni" -I "$host/cpp" -I "$repo_root/support-lib" -I "$repo_root/support-lib/jni" \
    -I "$java_home/include" -I "$java_home/include/darwin" "$f"
done
echo "HOST JNI C++ SYNTAX OK"
for f in "$host"/objc/*.mm; do
  "${CXX:-clang++}" -x objective-c++ -std=c++17 -fobjc-arc -fsyntax-only -I "$host/objc" -I "$host/cpp" \
    -I "$repo_root/support-lib" -I "$repo_root/support-lib/objc" "$f"
done
echo "HOST OBJECTIVE-C++ SYNTAX OK"

echo "== Runtime C++ (support-lib/swiftxx, objc/DataRef_objc.cpp): clang++ -fsyntax-only"
for f in "$repo_root"/support-lib/swiftxx/*.cpp "$repo_root/support-lib/objc/DataRef_objc.cpp"; do
  "${CXX:-clang++}" -std=c++20 -fsyntax-only -Wno-deprecated-declarations -DDATAREF_OBJC=1 \
    -I "$repo_root/support-lib/swiftxx" -I "$repo_root/support-lib" "$f"
done
echo "RUNTIME C++ SYNTAX OK"
