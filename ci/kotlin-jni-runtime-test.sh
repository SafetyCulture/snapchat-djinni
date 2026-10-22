#!/usr/bin/env bash
# Builds the generated JNI C++ with a C++ implementation, and runs Kotlin against it on the JVM.
#
# The test calls C++ from the generated Kotlin classes, and C++ calls a Kotlin object back. It checks
# records, outcomes, futures, C++ exceptions and many threads. A watchdog fails the run when it deadlocks.
# The script runs two programs: one against the classes without --kotlin-suspend-wrap, and one against the
# suspend functions that the flag makes. The script skips with exit code 77 and a message when something is
# missing: javac, java, kotlinc, clang++ (CXX), jni.h in JAVA_HOME, kotlin-stdlib.jar, kotlinx-coroutines,
# or a supported system (macOS, Linux). With CI or
# KOTLIN_JNI_RUNTIME_REQUIRED set, a missing part is an error (exit code 2).
#
# Environment:
#   JAVA_HOME          the JDK (default: derived from javac)
#   KOTLIN_LIB         directory of kotlinc with kotlin-stdlib.jar (default: derived from kotlinc)
#   KOTLINX_COROUTINES_JAR  kotlinx-coroutines-core-jvm.jar for the suspend mode (default: search ~/.gradle and ~/.m2)
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   CXX, CXXFLAGS      the C++ compiler (default: clang++) and extra flags for it
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
src="$repo_root/ci/kotlin-jni/runtime"

skip() {
  if [ -n "${CI:-}" ] || [ -n "${KOTLIN_JNI_RUNTIME_REQUIRED:-}" ]; then
    echo "MISSING: $1" >&2
    exit 2
  fi
  echo "SKIPPED: $1"
  exit 77
}

for tool in javac java kotlinc "${CXX:-clang++}"; do
  command -v "$tool" >/dev/null 2>&1 || skip "$tool is not installed"
done
# /usr/bin/javac on macOS is a launcher, so readlink would resolve java_home to /usr
java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ] && [ "$(uname -s)" = Darwin ] && [ -x /usr/libexec/java_home ]; then
  java_home="$(/usr/libexec/java_home 2>/dev/null || true)"
fi
java_home="${java_home:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
jni_include="$java_home/include"
[ -f "$jni_include/jni.h" ] || skip "jni.h is not in $jni_include (set JAVA_HOME)"
case "$(uname -s)" in
  Darwin) jni_platform="$jni_include/darwin"; lib_ext=dylib ;;
  Linux) jni_platform="$jni_include/linux"; lib_ext=so ;;
  *) skip "unsupported system $(uname -s)" ;;
esac
kotlin_lib="${KOTLIN_LIB:-}"
if [ -z "$kotlin_lib" ]; then
  kotlin_bin="$(dirname "$(readlink -f "$(command -v kotlinc)")")"
  for candidate in "$kotlin_bin/../lib" "$kotlin_bin/../libexec/lib"; do
    [ -f "$candidate/kotlin-stdlib.jar" ] && kotlin_lib="$(cd "$candidate" && pwd -P)" && break
  done
fi
[ -f "$kotlin_lib/kotlin-stdlib.jar" ] || skip "kotlin-stdlib.jar is not found (set KOTLIN_LIB)"

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-kotlin-runtime.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

out="$work/out"
generate() { # <kotlin out> [generator flags]
  local kotlin_out=$1
  shift
  (cd "$src" && java -jar "$jar" \
    --cpp-out "$out/cpp" --cpp-namespace kj \
    --jni-out "$out/jni" --jni-use-on-load-initializer false --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
    --java-package rt.kj --ident-java-field mFooBar \
    --kotlin-jni-out "$kotlin_out" "$@" \
    --idl runtime.djinni)
}
generate "$out/kotlin"

# The JNI library: the support library, the generated JNI code and the C++ implementation.
echo "== ${CXX:-clang++} ($(ls "$out"/jni/*.cpp | wc -l | tr -d ' ') generated JNI files)"
mkdir -p "$work/objs"
cxxflags=(-std=c++17 -fPIC -Wno-deprecated-declarations -DDATAREF_JNI=1 -I "$jni_include" -I "$jni_platform"
  -I "$out/cpp" -I "$out/jni" -I "$repo_root/support-lib/jni" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib")
for f in "$repo_root"/support-lib/jni/*.cpp "$out"/jni/*.cpp "$src/kj_service_impl.cpp"; do
  # shellcheck disable=SC2086
  "${CXX:-clang++}" "${cxxflags[@]}" ${CXXFLAGS:-} -c "$f" -o "$work/objs/$(basename "$f").o"
done
lib="$work/libkj.$lib_ext"
"${CXX:-clang++}" -shared -o "$lib" "$work"/objs/*.o

echo "== javac"
mkdir -p "$work/java-classes"
# shellcheck disable=SC2046
javac -Werror -Xlint:all -d "$work/java-classes" $(find "$repo_root/support-lib/java" -name '*.java')

# run_mode <name> <kotlin dir> <main file> <class path of the libraries> : compile the Kotlin and run it
run_mode() {
  local name=$1 kotlin_dir=$2 main=$3 libs=$4
  mkdir -p "$work/classes-$name"
  echo "== kotlinc and run: $name"
  kotlinc -Werror -d "$work/classes-$name" -cp "$work/java-classes:$libs" "$kotlin_dir" "$src/$main"
  java -Xcheck:jni -cp "$work/classes-$name:$work/java-classes:$libs" "rt.kj.${main%.kt}Kt" "$lib"
}
stdlib="$kotlin_lib/kotlin-stdlib.jar"
run_mode sync "$out/kotlin" Main.kt "$stdlib"

# The suspend functions need kotlinx-coroutines.
coroutines="${KOTLINX_COROUTINES_JAR:-}"
if [ -z "$coroutines" ]; then
  # Missing cache directories make find exit 1, which pipefail would turn into a script exit
  caches=(); for d in "$HOME/.gradle" "$HOME/.m2"; do [ -d "$d" ] && caches+=("$d"); done
  if [ "${#caches[@]}" -gt 0 ]; then
    coroutines="$(find "${caches[@]}" -name 'kotlinx-coroutines-core-jvm-*.jar' ! -name '*sources*' ! -name '*javadoc*' 2>/dev/null | awk -F/ '{print $NF "\t" $0}' | sort -V | tail -1 | cut -f2)"
  fi
fi
[ -n "$coroutines" ] && [ -f "$coroutines" ] || skip "kotlinx-coroutines-core-jvm.jar is not found (set KOTLINX_COROUTINES_JAR)"
echo "== coroutines: $coroutines"
generate "$out/kotlin-suspend" --kotlin-suspend-wrap
run_mode suspend "$out/kotlin-suspend" MainSuspend.kt "$stdlib:$coroutines"
