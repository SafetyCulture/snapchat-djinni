#!/usr/bin/env bash
# Builds the generated JNI C++ with a C++ implementation, and runs Kotlin against it on the JVM.
#
# The test calls C++ from the generated Kotlin classes, and C++ calls a Kotlin object back. It checks
# records, outcomes, futures, C++ exceptions and many threads. A watchdog fails the run when it deadlocks.
# The script skips with exit code 0 and a message when a tool is missing: javac, java, kotlinc,
# clang++, jni.h and the Kotlin standard library.
#
# Environment:
#   JAVA_HOME          the JDK (default: derived from javac)
#   KOTLIN_LIB         directory of kotlinc with kotlin-stdlib.jar (default: derived from kotlinc)
#   KOTLIN_FLAGS       extra generator flags, for example --kotlin-suspend-wrap
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
src="$repo_root/ci/kotlin-jni/runtime"

skip() { echo "SKIPPED: $1"; exit 0; }

for tool in javac java kotlinc "${CXX:-clang++}"; do
  command -v "$tool" >/dev/null 2>&1 || skip "$tool is not installed"
done
java_home="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
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
# shellcheck disable=SC2086
(cd "$src" && java -jar "$jar" \
  --cpp-out "$out/cpp" --cpp-namespace kj \
  --jni-out "$out/jni" --jni-use-on-load-initializer false --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
  --java-package rt.kj --ident-java-field mFooBar \
  --kotlin-jni-out "$out/kotlin" ${KOTLIN_FLAGS:-} \
  --idl runtime.djinni)

# The JNI library: the support library, the generated JNI code and the C++ implementation.
echo "== clang++ ($(ls "$out"/jni/*.cpp | wc -l | tr -d ' ') generated JNI files)"
mkdir -p "$work/objs"
cxxflags=(-std=c++17 -fPIC -Wno-deprecated-declarations -DDATAREF_JNI=1 -I "$jni_include" -I "$jni_platform"
  -I "$out/cpp" -I "$out/jni" -I "$repo_root/support-lib/jni" -I "$repo_root/support-lib/cpp" -I "$repo_root/support-lib")
for f in "$repo_root"/support-lib/jni/*.cpp "$out"/jni/*.cpp "$src/kj_service_impl.cpp"; do
  "${CXX:-clang++}" "${cxxflags[@]}" -c "$f" -o "$work/objs/$(basename "$f").o"
done
lib="$work/libkj.$lib_ext"
"${CXX:-clang++}" -shared -o "$lib" "$work"/objs/*.o

# The JVM side: the Java support library, the generated Kotlin and the test program.
echo "== javac and kotlinc"
mkdir -p "$work/java-classes" "$work/kotlin-classes"
# shellcheck disable=SC2046
javac -nowarn -d "$work/java-classes" $(find "$repo_root/support-lib/java" -name '*.java')
coroutines="${KOTLINX_COROUTINES_JAR:-}"
classpath="$work/java-classes:$kotlin_lib/kotlin-stdlib.jar${coroutines:+:$coroutines}"
kotlinc -nowarn -d "$work/kotlin-classes" -cp "$classpath" "$out/kotlin" "$src/Main.kt"
echo "== run"
java -Xcheck:jni -cp "$work/kotlin-classes:$classpath" rt.kj.MainKt "$lib"
