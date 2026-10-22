#!/usr/bin/env bash
# Proves that the Kotlin classes of --kotlin-jni-out bind to the JNI code that goes with the Java classes.
#
# For two IDL sets the script generates Java, JNI C++ and Kotlin with the same flags, compiles the Java
# and the Kotlin on the JVM, and compares the class files with `javap -p -s` (ci/kotlin_jni_compare.py):
# the Crux assets IDL with the flags of crux/tools/generate_code.sh, and the test-suite IDL.
#
# Needs javac, javap and kotlinc. The Kotlin compiler needs its Parcelize plugin (parcelize-compiler.jar).
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   KOTLIN_LIB         directory of kotlinc with parcelize-compiler.jar (default: derived from kotlinc)
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:-$HOME/Desktop/safetyculture/mitti-mobile}"
domain_dir="$mitti_root/crux/djinni/domain"
extern_src="$mitti_root/crux/deps/APISchema/_generated/crux/cpp"

kotlin_lib="${KOTLIN_LIB:-}"
if [ -z "$kotlin_lib" ]; then
  kotlin_bin="$(dirname "$(readlink -f "$(command -v kotlinc)")")"
  for candidate in "$kotlin_bin/../lib" "$kotlin_bin/../libexec/lib"; do
    [ -f "$candidate/parcelize-compiler.jar" ] && kotlin_lib="$(cd "$candidate" && pwd -P)" && break
  done
fi
[ -f "$kotlin_lib/parcelize-compiler.jar" ] || { echo "parcelize-compiler.jar not found, set KOTLIN_LIB" >&2; exit 2; }
for d in "$domain_dir" "$extern_src"; do
  [ -d "$d" ] || { echo "missing directory: $d (set MITTI_MOBILE_ROOT)" >&2; exit 2; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-kotlin-jni.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

# compile_and_compare <name> <package> <extern dir or ""> : the generated trees are in $work/<name>/{java,jni,kotlin}
compile_and_compare() {
  local name=$1 package=$2 extern=$3 dir="$work/$1"
  mkdir -p "$dir/stubs" "$dir/java-classes" "$dir/kotlin-classes"
  [ -z "$extern" ] || python3 "$repo_root/ci/kotlin_jni_stubs.py" "$extern" "$dir/stubs"
  # The test suite uses javax.annotation annotations.
  mkdir -p "$dir/stubs/javax/annotation"
  printf 'package javax.annotation;\npublic @interface CheckForNull {}\n' >"$dir/stubs/javax/annotation/CheckForNull.java"
  printf 'package javax.annotation;\npublic @interface Nonnull {}\n' >"$dir/stubs/javax/annotation/Nonnull.java"
  echo "== $name: javac ($(find "$dir/java" -name '*.java' | wc -l | tr -d ' ') Java files)"
  # shellcheck disable=SC2046
  javac -nowarn -d "$dir/java-classes" $(find "$dir/stubs" "$dir/java" "$repo_root/ci/kotlin-jni/stubs" "$repo_root/support-lib/java" -name '*.java')
  echo "== $name: kotlinc ($(find "$dir/kotlin" -name '*.kt' | wc -l | tr -d ' ') Kotlin files)"
  kotlinc -nowarn -d "$dir/kotlin-classes" -Xplugin="$kotlin_lib/parcelize-compiler.jar" \
    -cp "$dir/java-classes:$kotlin_lib/parcelize-runtime.jar" "$dir/kotlin"
  echo "== $name: javap"
  python3 "$repo_root/ci/kotlin_jni_compare.py" "$dir/java-classes" "$dir/kotlin-classes" "$dir/jni" "$package"
}

# 1. Crux assets IDL, with the flags of crux/tools/generate_code.sh. The names of the fields are the Java names (mFooBar).
package=com.safetyculture.crux.domain
python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx" "$repo_root" "common.djinni,media.djinni,assets.djinni"
(cd "$work/fx" && java -jar "$jar" \
  --java-out "$work/crux/java" --java-package "$package" --ident-java-field mFooBar \
  --cpp-out "$work/crux/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h \
  --java-nonnull-annotation androidx.annotation.NonNull \
  --jni-out "$work/crux/jni" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar --ident-cpp-method FooBar \
  --jni-include-cpp-prefix generated/ --java-implement-android-os-parcelable true \
  --kotlin-jni-out "$work/crux/kotlin" --kotlin-jni-package "$package" \
  --idl-include-path extern --idl crux/djinni/domain/swift_fixture.djinni)
compile_and_compare crux "$package" "$work/fx/extern"

# The Kotlin property has the Java field name, and the JNI code looks up that name.
if ! grep -q "val mAsset:" "$work/crux/kotlin/AssetResult.kt" || ! grep -q 'jniGetFieldID(clazz.get(), "mAsset"' "$work/crux/jni"/NativeAssetResult.*; then
  echo "FAIL: the Kotlin property of a record has not the name of the Java field" >&2
  exit 1
fi
echo "record field: Kotlin 'val mAsset' and JNI GetFieldID \"mAsset\""

# 2. The test-suite IDL, with the flags of test-suite/run_djinni.sh.
package=com.dropbox.djinni.test
mkdir -p "$work/suite"
(cd "$repo_root/test-suite" && java -jar "$jar" \
  --java-out "$work/suite/java" --jni-out "$work/suite/jni" --kotlin-jni-out "$work/suite/kotlin" \
  --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
  --java-nonnull-annotation javax.annotation.Nonnull --java-use-final-for-record false \
  --java-implement-android-os-parcelable true --ident-java-field mFooBar \
  --cpp-out "$work/suite/cpp" --cpp-namespace testsuite --ident-cpp-enum-type foo_bar \
  --cpp-optional-template "std::experimental::optional" --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
  --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
  --jni-use-on-load-initializer false --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
  --idl djinni/kotlin_jni.djinni --idl-include-path djinni/vendor)
compile_and_compare suite "$package" ""
echo "KOTLIN JNI CHECK OK"
