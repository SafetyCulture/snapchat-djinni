#!/usr/bin/env bash
# Builds the generated JNI C++ with a C++ implementation, and runs Kotlin against it on the JVM.
#
# The test calls C++ from the generated Kotlin classes, and C++ calls a Kotlin object back. It checks
# records, outcomes, futures, C++ exceptions and many threads. A watchdog fails the run when it deadlocks.
# One program builds two glue sets of one IDL into one library, to check that each leg gets its own proxy.
# The script runs these programs: one against the classes without --kotlin-suspend-wrap, and one against the
# suspend functions that the flag makes. The second program runs with the default dispatcher and with
# --kotlin-suspend-dispatcher. Two more programs check --kotlin-error-type: with blocking functions
# (runtime_sync.djinni, which has no future) and with suspend functions (runtime.djinni). The script skips with
# exit code 77 and a message when something is missing: javac, java, kotlinc, clang++ (CXX), jni.h in JAVA_HOME,
# kotlin-stdlib.jar, kotlinx-coroutines, or a supported system (macOS, Linux). With CI or
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
generate() { # <idl> <C++ and JNI out> <kotlin out> [generator flags]
  local idl=$1 gen_out=$2 kotlin_out=$3
  shift 3
  (cd "$src" && java -jar "$jar" \
    --cpp-out "$gen_out/cpp" --cpp-namespace kj \
    --jni-out "$gen_out/jni" --jni-use-on-load-initializer false --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
    --java-package rt.kj --ident-java-field mFooBar \
    --kotlin-jni-out "$kotlin_out" "$@" \
    --idl "$idl")
}
generate runtime.djinni "$out" "$out/kotlin"
# The IDL without futures, for --kotlin-error-type without --kotlin-suspend-wrap
out_sync="$work/out-sync"
generate runtime_sync.djinni "$out_sync" "$out_sync/kotlin" --kotlin-error-type rt.kj.KjsException

# The JNI libraries: the support library, the generated JNI code and the C++ implementation.
cxxflags=(-std=c++17 -fPIC -Wno-deprecated-declarations -DDATAREF_JNI=1 -I "$jni_include" -I "$jni_platform"
  -I "$repo_root/support-lib/jni" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib"
  -I "$repo_root/ci/kotlin-jni/extern")
compile() { # <generated dir> <source> <object>
  # shellcheck disable=SC2086
  "${CXX:-clang++}" "${cxxflags[@]}" -I "$1/cpp" -I "$1/jni" ${CXXFLAGS:-} -c "$2" -o "$3"
}
mkdir -p "$work/objs/support"
for f in "$repo_root"/support-lib/jni/*.cpp; do
  compile "$out" "$f" "$work/objs/support/$(basename "$f").o"
done
build_lib() { # <library file> <generated dir> <C++ implementation>
  local lib_file=$1 gen=$2 impl=$3 objs
  objs="$work/objs/$(basename "$lib_file")"
  echo "== ${CXX:-clang++} $(basename "$lib_file") ($(ls "$gen"/jni/*.cpp | wc -l | tr -d ' ') generated JNI files)"
  mkdir -p "$objs"
  for f in "$gen"/jni/*.cpp "$impl"; do
    compile "$gen" "$f" "$objs/$(basename "$f").o"
  done
  "${CXX:-clang++}" -shared -o "$lib_file" "$work"/objs/support/*.o "$objs"/*.o
}
lib="$work/libkj.$lib_ext"
build_lib "$lib" "$out" "$src/kj_service_impl.cpp"
lib_sync="$work/libkjs.$lib_ext"
build_lib "$lib_sync" "$out_sync" "$src/kjs_service_impl.cpp"

echo "== javac"
mkdir -p "$work/java-classes"
# shellcheck disable=SC2046
javac -Werror -Xlint:all -d "$work/java-classes" $(find "$repo_root/support-lib/java" -name '*.java')

# run_mode <name> <JNI library> <kotlin dir> <main file> <class path of the libraries> <Kotlin files, ':' separated>
#   [<program arguments>...] : compile the Kotlin and run it
run_mode() {
  local name=$1 native=$2 kotlin_dir=$3 main=$4 libs=$5 extra
  IFS=: read -r -a extra <<<"$6"
  shift 6
  mkdir -p "$work/classes-$name"
  echo "== kotlinc and run: $name"
  kotlinc -Werror -d "$work/classes-$name" -cp "$work/java-classes:$libs" "$kotlin_dir" "$src/$main" "${extra[@]}"
  java -Xcheck:jni -cp "$work/classes-$name:$work/java-classes:$libs" "rt.kj.${main%.kt}Kt" "$native" "$@" 2>&1 | tee "$work/java-$name.log"
  if grep -q "WARNING in native method" "$work/java-$name.log"; then
    echo "FAIL: -Xcheck:jni reported a warning in $name" >&2
    exit 1
  fi
}
stdlib="$kotlin_lib/kotlin-stdlib.jar"
runtime_kotlin="$repo_root/ci/kotlin-jni/extern/ExternKotlinMessage.kt:$src/KjExtendedSub.kt"
run_mode sync "$lib" "$out/kotlin" Main.kt "$stdlib" "$runtime_kotlin"
# The error type of the application with blocking functions.
run_mode typed "$lib_sync" "$out_sync/kotlin" MainTyped.kt "$stdlib" "$src/KjsException.kt"

# Two glue sets of one IDL in one library: Java classes with JNI namespace glue_a, and Kotlin JNI classes with
# namespace glue_b. Each leg must get a proxy of its own class for one C++ object.
out_a="$work/two-a"
out_b="$work/two-b"
mkdir -p "$out_a" "$out_b"
echo "== two glue sets: generator run A (Java classes, JNI namespace glue_a)"
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out_a/cpp" --cpp-namespace tg \
  --jni-out "$out_a/jni" --jni-namespace glue_a --jni-use-on-load-initializer false \
  --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
  --java-out "$out_a/java" --java-package rt.two.a --ident-java-field mFooBar \
  --idl two_glue.djinni)
echo "== two glue sets: generator run B (Kotlin JNI classes, JNI namespace glue_b)"
(cd "$src" && java -jar "$jar" \
  --cpp-namespace tg \
  --jni-out "$out_b/jni/b" --jni-namespace glue_b --jni-include-prefix b/ --jni-use-on-load-initializer false \
  --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
  --kotlin-jni-out "$out_b/kotlin" --java-package rt.two.b \
  --idl two_glue.djinni)
echo "== ${CXX:-clang++} libtwo.$lib_ext ($(ls "$out_a"/jni/*.cpp "$out_b"/jni/b/*.cpp | wc -l | tr -d ' ') JNI files of both glue sets)"
objs="$work/objs/two"
mkdir -p "$objs"
for f in "$out_a"/jni/*.cpp "$out_b"/jni/b/*.cpp; do
  side="a"
  case "$f" in "$out_b"/*) side="b" ;; esac
  # shellcheck disable=SC2086
  "${CXX:-clang++}" "${cxxflags[@]}" -I "$out_a/cpp" -I "$out_a/jni" -I "$out_b/jni" ${CXXFLAGS:-} \
    -c "$f" -o "$objs/$side-$(basename "$f").o"
done
# shellcheck disable=SC2086
"${CXX:-clang++}" "${cxxflags[@]}" -I "$out_a/cpp" ${CXXFLAGS:-} -c "$src/two_glue_impl.cpp" -o "$objs/impl.o"
"${CXX:-clang++}" -shared -o "$work/libtwo.$lib_ext" "$work"/objs/support/*.o "$objs"/*.o

echo "== javac, kotlinc and run: two_glue"
mkdir -p "$work/java-two-classes" "$work/classes-two_glue"
# shellcheck disable=SC2046
javac -nowarn -d "$work/java-two-classes" $(find "$out_a/java" "$repo_root/support-lib/java" -name '*.java')
kotlinc -Werror -d "$work/classes-two_glue" -cp "$work/java-two-classes:$stdlib" "$out_b/kotlin" "$src/TwoGlueMain.kt"
java -Xcheck:jni -cp "$work/classes-two_glue:$work/java-two-classes:$stdlib" rt.two.TwoGlueMainKt "$work/libtwo.$lib_ext" 2>&1 | tee "$work/java-two_glue.log"
if grep -q "WARNING in native method" "$work/java-two_glue.log"; then
  echo "FAIL: -Xcheck:jni reported a warning in two_glue" >&2
  exit 1
fi

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
generate runtime.djinni "$out" "$out/kotlin-suspend" --kotlin-suspend-wrap
run_mode suspend "$lib" "$out/kotlin-suspend" MainSuspend.kt "$stdlib:$coroutines" "$runtime_kotlin"
# The same program with the dispatcher of the application: the C++ calls run on its threads.
generate runtime.djinni "$out" "$out/kotlin-suspend-dispatcher" --kotlin-suspend-wrap --kotlin-suspend-dispatcher rt.kj.TestDispatchers.blocking
run_mode suspend-dispatcher "$lib" "$out/kotlin-suspend-dispatcher" MainSuspend.kt "$stdlib:$coroutines" "$runtime_kotlin" kj-blocking
# The error type of the application with suspend functions.
generate runtime.djinni "$out" "$out/kotlin-typed-suspend" --kotlin-suspend-wrap --kotlin-error-type rt.kj.KjException
run_mode typed-suspend "$lib" "$out/kotlin-typed-suspend" MainTypedSuspend.kt "$stdlib:$coroutines" "$runtime_kotlin:$src/KjException.kt"
