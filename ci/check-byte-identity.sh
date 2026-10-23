#!/usr/bin/env bash
# Proves that a change leaves the output of the existing generators byte-identical.
#
# It builds the generator at the working tree and at BASE_REF, runs both over every Crux
# IDL file with the flags crux/tools/generate_code.sh passes, and diffs the output trees.
# A second pass adds the ts, wasm and yaml generators. The script exits 0 only when both
# diffs are empty. Exit codes and stderr of each run are part of the compared output.
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   BASE_REF           git ref to compare against (default: origin/main)
#   BASE_JAR, HEAD_JAR prebuilt //src:djinni_deploy.jar files, skips the Bazel build
#   BAZEL              Bazel executable (default: bazel)
#   BAZEL_ARGS         extra Bazel arguments, for example a macOS toolchain override
#   KEEP_OUT           set to 1 to keep the work directory
#   JOBS               parallel generator runs (default: 4)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:-$HOME/Desktop/safetyculture/mitti-mobile}"
base_ref="${BASE_REF:-origin/main}"
bazel="${BAZEL:-bazel}"
jobs="${JOBS:-4}"
domain_dir="$mitti_root/crux/djinni/domain"
testing_dir="$mitti_root/crux/djinni/testing_support"
extern_dir="$mitti_root/crux/deps/APISchema/_generated/crux/cpp"

for d in "$domain_dir" "$testing_dir" "$extern_dir"; do
  [ -d "$d" ] || { echo "missing directory: $d (set MITTI_MOBILE_ROOT)" >&2; exit 2; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-identity.XXXXXX")"
base_tree="$work/base-tree"
cleanup() {
  if [ -d "$base_tree" ]; then git -C "$repo_root" worktree remove --force "$base_tree" >/dev/null 2>&1 || true; fi
  if [ "${KEEP_OUT:-0}" != 1 ]; then rm -rf "$work"; else echo "kept: $work"; fi
}
trap cleanup EXIT

build_jar() { # <source tree> <output jar>
  # shellcheck disable=SC2086
  (cd "$1" && "$bazel" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2 && cp -f bazel-bin/src/djinni_deploy.jar "$2")
}

if [ -n "${HEAD_JAR:-}" ]; then cp "$HEAD_JAR" "$work/head.jar"; else build_jar "$repo_root" "$work/head.jar"; fi
if [ -n "${BASE_JAR:-}" ]; then
  cp "$BASE_JAR" "$work/base.jar"
else
  git -C "$repo_root" worktree add --detach "$base_tree" "$base_ref" >&2
  build_jar "$base_tree" "$work/base.jar"
fi

# One generator run. Flags mirror run_djinni in crux/tools/generate_code.sh.
run_one() { # <jar> <idl> <out dir> <cpp ns> <objc prefix> <java pkg> <objc dir> <kotlin pkg> <kotlin support pkg> <kotlin cinterop pkg> <pass>
  local jar=$1 idl=$2 out=$3 cpp_ns=$4 prefix=$5 jpkg=$6 objc_dir=$7 kpkg=$8 ksup=$9 kcin=${10} pass=${11}
  local inc="generated"
  local -a args=(
    --java-out "$out/java/$(echo "$jpkg" | tr . /)" --java-package "$jpkg"
    --ident-java-field mFooBar
    --cpp-out "$out/cpp/$inc" --cpp-namespace "$cpp_ns" --cpp-ext cc --hpp-ext h
    --java-nonnull-annotation androidx.annotation.NonNull
    --jni-out "$out/jni" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar
    --ident-cpp-method FooBar
    --objc-out "$out/objc/public/$objc_dir" --objc-type-prefix "$prefix"
    --objcpp-out "$out/objc/private" --objc-disable-class-ctor true
    --jni-include-cpp-prefix "$inc/" --objcpp-include-cpp-prefix "$inc/"
    --java-implement-android-os-parcelable true
    --kotlin-out "$out/kotlin"
    --idl-include-path "$extern_dir" --list-in-files "$out/.in-files" --idl "$idl"
  )
  args+=(--kotlin-package "$kpkg" --kotlin-support-package "$ksup" --kotlin-cinterop-package "$kcin")
  if [ "$pass" = extra ]; then
    args+=(--ts-out "$out/ts" --ts-module crux --wasm-out "$out/wasm" --wasm-namespace crux --yaml-out "$out/yaml")
  fi
  mkdir -p "$out"
  local code=0
  (cd "$out" && java -jar "$jar" "${args[@]}" >"$out/.stdout" 2>"$out/.stderr") || code=$?
  echo "$code" >"$out/.exit"
  # The generator prints absolute paths of its inputs and outputs; normalise them.
  sed -i.bak -e "s#$work/[a-z]*-out/[^ ]*#<out>#g" -e "s#$mitti_root#<mitti>#g" "$out/.stdout" "$out/.stderr"
  rm -f "$out"/.stdout.bak "$out"/.stderr.bak
}

jobs_file="$work/jobs.txt"
: >"$jobs_file"
add_jobs() { # <pass>
  local pass=$1
  for side in base head; do
    echo "$side $pass $domain_dir/main.djinni domain/main CRX com.safetyculture.crux.domain Crux crux::generated com.safetyculture.scmobile.cruxinterop.bindings com.safetyculture.djinni.support Crux" >>"$jobs_file"
    echo "$side $pass $testing_dir/main.djinni testing_support/main CTS com.safetyculture.crux.testing_support CruxTestingSupport crux::testing_support::generated - - -" >>"$jobs_file"
  done
}
add_jobs exact
add_jobs extra

export -f run_one
export work mitti_root extern_dir
# shellcheck disable=SC2016
xargs -P "$jobs" -L 1 bash -c '
  side=$0; pass=$1; idl=$2; label=$3; prefix=$4; jpkg=$5; objc_dir=$6; cpp_ns=$7; kpkg=$8; ksup=$9; kcin=${10}
  [ "$kpkg" = - ] && { kpkg=""; ksup=""; kcin=""; }
  run_one "$work/$side.jar" "$idl" "$work/$side-out/$pass/$label" "$cpp_ns" "$prefix" "$jpkg" "$objc_dir" "$kpkg" "$ksup" "$kcin" "$pass"
' <"$jobs_file"

status=0
# main.djinni imports every other file, as in crux/tools/generate_code.sh. Fail if a file is missing.
for f in "$domain_dir"/*.djinni; do
  grep -qx "$f" "$work/head-out/exact/domain/main/.in-files" || {
    echo "not covered by main.djinni: $f" >&2; status=1; }
done
echo "domain idl files: $(ls "$domain_dir"/*.djinni | wc -l | tr -d ' ') (all in the import closure of main.djinni unless listed above)"
for pass in exact extra; do
  files="$(find "$work/base-out/$pass" -type f | wc -l | tr -d ' ')"
  runs="$(find "$work/base-out/$pass" -name .exit | wc -l | tr -d ' ')"
  failed="$(grep -L '^0$' "$work"/base-out/"$pass"/*/*/.exit 2>/dev/null | wc -l | tr -d ' ')"
  echo "pass=$pass runs=$runs files=$files runs-with-nonzero-exit=$failed"
  [ "$failed" = 0 ] || { echo "a generator run failed; see $work" >&2; KEEP_OUT=1; status=1; }
  if diff -r "$work/base-out/$pass" "$work/head-out/$pass"; then
    echo "pass=$pass: diff -r base head is empty"
  else
    echo "pass=$pass: outputs differ" >&2
    status=1
  fi
done
[ "$status" = 0 ] && echo "BYTE-IDENTICAL: base=$base_ref head=$(git -C "$repo_root" rev-parse --short HEAD) (+ working tree)"
exit "$status"
