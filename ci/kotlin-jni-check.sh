#!/usr/bin/env bash
# Proves that the Kotlin classes of --kotlin-jni-out bind to the JNI code that goes with the Java classes.
#
# For several IDL sets the script generates Java, JNI C++ and Kotlin with the same flags, compiles the Java
# and the Kotlin on the JVM, and compares the class files with `javap -p -s` (ci/kotlin_jni_compare.py):
# the Crux assets IDL with the flags of crux/tools/generate_code.sh, the whole Crux IDL with --kotlin-error-type
# and --kotlin-suspend-wrap, and the test-suite IDL.
#
# Needs javac, javap and kotlinc. The Kotlin compiler needs its Parcelize plugin (parcelize-compiler.jar).
#
# Environment:
#   MITTI_MOBILE_ROOT  mitti-mobile checkout that holds crux/djinni and the extern yaml files
#   KOTLIN_JNI_CHECK_CRUX  set to 0 to skip the Crux IDL (passes 1 and 1b), which needs MITTI_MOBILE_ROOT
#   KOTLIN_LIB         directory of kotlinc with parcelize-compiler.jar (default: derived from kotlinc)
#   KOTLINX_COROUTINES_JAR  kotlinx-coroutines-core-jvm.jar for --kotlin-suspend-wrap (default: search ~/.gradle and ~/.m2)
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL, BAZEL_ARGS  as in check-byte-identity.sh
#   KEEP_OUT           set to 1 to keep the work directory
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
mitti_root="${MITTI_MOBILE_ROOT:-}"
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
coroutines="${KOTLINX_COROUTINES_JAR:-}"
if [ -z "$coroutines" ]; then
  # Missing cache directories make find exit 1, which pipefail would turn into a script exit
  caches=(); for d in "$HOME/.gradle" "$HOME/.m2"; do [ -d "$d" ] && caches+=("$d"); done
  if [ "${#caches[@]}" -gt 0 ]; then
    coroutines="$(find "${caches[@]}" -name 'kotlinx-coroutines-core-jvm-*.jar' ! -name '*sources*' ! -name '*javadoc*' 2>/dev/null | awk -F/ '{print $NF "\t" $0}' | sort -V | tail -1 | cut -f2)"
  fi
fi
[ -n "$coroutines" ] && [ -f "$coroutines" ] || { echo "kotlinx-coroutines-core-jvm.jar not found, set KOTLINX_COROUTINES_JAR" >&2; exit 2; }
echo "== coroutines: $coroutines"
check_crux="${KOTLIN_JNI_CHECK_CRUX:-1}"
if [ "$check_crux" != 0 ]; then
  [ -n "$mitti_root" ] || { echo "set MITTI_MOBILE_ROOT to a mitti-mobile checkout, or KOTLIN_JNI_CHECK_CRUX=0" >&2; exit 2; }
  for d in "$domain_dir" "$extern_src"; do
    [ -d "$d" ] || { echo "missing directory: $d (set MITTI_MOBILE_ROOT)" >&2; exit 2; }
  done
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-kotlin-jni.XXXXXX")"
trap '[ "${KEEP_OUT:-0}" = 1 ] && echo "kept: $work" || rm -rf "$work"' EXIT

if [ -n "${HEAD_JAR:-}" ]; then
  jar="$HEAD_JAR"
else
  # shellcheck disable=SC2086
  (cd "$repo_root" && "${BAZEL:-bazel}" build ${BAZEL_ARGS:-} //src:djinni_deploy.jar >&2)
  jar="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

# compile_and_compare <name> <package> <extern dir or ""> [<extra Kotlin dir> [<arguments of kotlin_jni_compare.py>...]]
# The generated trees are in $work/<name>/{java,jni,kotlin}.
compile_and_compare() {
  local name=$1 package=$2 extern=$3 dir="$work/$1"
  shift 3
  local extra_kotlin="${1:-}"
  [ $# -eq 0 ] || shift
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
  kotlinc -Werror -d "$dir/kotlin-classes" -Xplugin="$kotlin_lib/parcelize-compiler.jar" \
    -cp "$dir/java-classes:$kotlin_lib/parcelize-runtime.jar:$coroutines" "$dir/kotlin" ${extra_kotlin:+"$extra_kotlin"}
  echo "== $name: javap"
  python3 "$repo_root/ci/kotlin_jni_compare.py" "$dir/java-classes" "$dir/kotlin-classes" "$dir/jni" "$package" "$@"
}

# strip_kotlin_keys <extern dir>: removes the Kotlin keys (jni.kotlin*, kotlin.jniTypename) from the yaml files.
# The Crux passes generate Java, Kotlin and JNI in one run, which binds one class for each extern type, and the
# committed s12 asset yaml has the Kotlin keys; pass 4 checks the extern types with the Kotlin keys.
strip_kotlin_keys() {
  python3 - "$1" <<'EOF'
import glob, os, re, sys
for path in glob.glob(os.path.join(sys.argv[1], "**", "*.yaml"), recursive=True):
    text = open(path).read()
    stripped = re.sub(r"^  (kotlinTranslator|kotlinHeader|kotlinTypeSignature|jniTypename): .*\n", "", text, flags=re.M)
    # A kotlin block that had only jniTypename is now empty
    stripped = re.sub(r"^kotlin:\n(?!  )", "", stripped, flags=re.M)
    if stripped != text:
        open(path, "w").write(stripped)
EOF
}

# 1. Crux assets IDL, with the flags of crux/tools/generate_code.sh. The names of the fields are the Java names (mFooBar).
if [ "$check_crux" != 0 ]; then
  package=com.safetyculture.crux.domain
  python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx" "$repo_root" "common.djinni,media.djinni,assets.djinni"
  strip_kotlin_keys "$work/fx/extern"
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

  # 1b. The whole Crux IDL (main.djinni) with the error type of the application and suspend functions. Crux has no
  # error record, so the pass adds the record crux_error for the constructor (error: E) of the class.
  python3 "$repo_root/ci/swift_fixtures.py" "$domain_dir" "$extern_src" "$work/fx-main" "$repo_root" "main.djinni"
  strip_kotlin_keys "$work/fx-main/extern"
  printf 'crux_error = record {\n  message: string;\n  code: i32;\n}\n' >"$work/fx-main/crux/djinni/domain/crux_error.djinni"
  printf '@import "crux_error.djinni"\n' >>"$work/fx-main/crux/djinni/domain/swift_fixture.djinni"
  (cd "$work/fx-main" && java -jar "$jar" \
    --java-out "$work/crux-error/java" --java-package "$package" --ident-java-field mFooBar \
    --cpp-out "$work/crux-error/cpp/generated" --cpp-namespace crux::generated --cpp-ext cc --hpp-ext h \
    --java-nonnull-annotation androidx.annotation.NonNull \
    --jni-out "$work/crux-error/jni" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar --ident-cpp-method FooBar \
    --jni-include-cpp-prefix generated/ --java-implement-android-os-parcelable true \
    --kotlin-jni-out "$work/crux-error/kotlin" --kotlin-jni-package "$package" \
    --kotlin-suspend-wrap --kotlin-error-type "$package.CruxException" \
    --idl-include-path extern --idl crux/djinni/domain/swift_fixture.djinni)
  compile_and_compare crux-error "$package" "$work/fx-main/extern" "$repo_root/ci/kotlin-jni/crux"
  # The flag must change the Crux output: a static method throws the class, and a future is a suspend function.
  if ! grep -q "throw $package.CruxException(djinni_e)" "$work/crux-error/kotlin/CruxAPI.kt" ||
     ! grep -q "suspend fun downloadAsset(groupId: String, remoteUrl: String): String?" "$work/crux-error/kotlin/TrainingOfflineAssetManager.kt"; then
    echo "FAIL: --kotlin-error-type did not change the Crux output" >&2
    exit 1
  fi
  echo "crux error type: $(grep -l "$package.CruxException" "$work/crux-error/kotlin"/*.kt | wc -l | tr -d ' ') Kotlin files throw CruxException"
fi

# 2. The test-suite IDL, with the flags of test-suite/run_djinni.sh. The second run registers the natives in JNI_OnLoad.
package=com.dropbox.djinni.test
for mode in suite:false suite-onload:true; do
  name="${mode%%:*}"
  mkdir -p "$work/$name"
  (cd "$repo_root/test-suite" && java -jar "$jar" \
    --java-out "$work/$name/java" --jni-out "$work/$name/jni" --kotlin-jni-out "$work/$name/kotlin" \
    --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
    --java-nonnull-annotation javax.annotation.Nonnull --java-use-final-for-record false \
    --java-implement-android-os-parcelable true --java-gen-interface true --ident-java-field mFooBar \
    --cpp-out "$work/$name/cpp" --cpp-namespace testsuite --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    --jni-use-on-load-initializer "${mode##*:}" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
    --idl djinni/kotlin_jni.djinni --idl-include-path djinni/vendor)
  compile_and_compare "$name" "$package" ""
done

# 3. Suspend functions, also with the registration in JNI_OnLoad. The natives, the lookups and the fields must not change.
for mode in suspend:false suspend-onload:true; do
  name="${mode%%:*}"
  mkdir -p "$work/$name"
  (cd "$repo_root/test-suite" && java -jar "$jar" \
    --java-out "$work/$name/java" --jni-out "$work/$name/jni" --kotlin-jni-out "$work/$name/kotlin" --kotlin-suspend-wrap \
    --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
    --java-nonnull-annotation javax.annotation.Nonnull --ident-java-field mFooBar \
    --cpp-out "$work/$name/cpp" --cpp-namespace testsuite \
    --jni-use-on-load-initializer "${mode##*:}" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
    --idl djinni/kotlin_suspend.djinni)
  compile_and_compare "$name" "$package" ""
done

# A record named unit is not Unit. A future<unit> returns the record, and only a future<void> has no value.
suspend_kt="$work/suspend/kotlin/KotlinSuspendService.kt"
if ! grep -qF "abstract suspend fun loadUnit(): Unit" "$suspend_kt" || ! grep -qF "abstract suspend fun flush()" "$suspend_kt" ||
   grep -F "abstract suspend fun flush()" "$suspend_kt" | grep -q ": "; then
  echo "FAIL: a future<unit> of a record named unit loses its value, or a future<void> has a value" >&2
  exit 1
fi
echo "suspend functions: future<unit> returns the record, future<void> returns nothing"

# A suspend function cannot override a member of Any, so the generator rejects it and writes no file.
name=suspend-any-names
mkdir -p "$work/$name"
set +e
(cd "$repo_root/test-suite" && java -jar "$jar" \
  --kotlin-jni-out "$work/$name/kotlin" --kotlin-suspend-wrap --java-package "$package" \
  --idl djinni/kotlin_suspend_any_names.djinni) >"$work/$name/out.log" 2>&1
status=$?
set -e
expected="interface kotlin_suspend_any_names, method to_string: --kotlin-suspend-wrap makes a suspend function, which cannot override toString of Any. Rename the method."
if [ "$status" -ne 1 ] || ! grep -qF -- "$expected" "$work/$name/out.log" || [ -e "$work/$name/kotlin" ]; then
  echo "FAIL: the generator accepted a suspend function with the name of a member of Any, or wrote files (exit $status)" >&2
  cat "$work/$name/out.log" >&2
  exit 1
fi
echo "suspend functions: a method with the name of a member of Any is rejected"

# 3b. The error type of the application, with blocking functions and with suspend functions. The natives, the
# lookups and the fields must not change. The JNI code binds by name in the first run and in JNI_OnLoad in the second.
for mode in error-sync:kotlin_error::false error-suspend:kotlin_error_async:--kotlin-suspend-wrap:true; do
  IFS=: read -r name idl suspend onload <<<"$mode"
  mkdir -p "$work/$name"
  (cd "$repo_root/test-suite" && java -jar "$jar" \
    --java-out "$work/$name/java" --jni-out "$work/$name/jni" --kotlin-jni-out "$work/$name/kotlin" ${suspend:+"$suspend"} \
    --kotlin-error-type com.dropbox.djinni.test.KotlinErrorException \
    --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
    --java-nonnull-annotation javax.annotation.Nonnull --ident-java-field mFooBar \
    --cpp-out "$work/$name/cpp" --cpp-namespace testsuite \
    --jni-use-on-load-initializer "$onload" --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
    --idl "djinni/$idl.djinni")
  compile_and_compare "$name" "$package" "" "$repo_root/ci/kotlin-jni/error"
done

# 4. Extern records with the Kotlin keys. The JNI code binds one class for each extern type, so Java and Kotlin
# are generated apart. The Java classes are the reference: the Kotlin class of the extern type replaces its
# Java class in their descriptors. The header of the translator is a copy of the form that the Crux plugin writes.
name=extern
mkdir -p "$work/$name/yaml"
cp "$repo_root/test-suite/djinni/vendor/third-party/kotlin_extern.yaml" "$work/$name/yaml/"
(cd "$repo_root/test-suite" && java -jar "$jar" \
  --java-out "$work/$name/java" --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
  --java-nonnull-annotation javax.annotation.Nonnull --ident-java-field mFooBar --java-implement-android-os-parcelable true \
  --idl djinni/kotlin_extern.djinni --idl-include-path djinni/vendor)
(cd "$repo_root/test-suite" && java -jar "$jar" \
  --jni-out "$work/$name/jni" --kotlin-jni-out "$work/$name/kotlin" \
  --java-package "$package" --java-nullable-annotation javax.annotation.CheckForNull \
  --java-nonnull-annotation javax.annotation.Nonnull --ident-java-field mFooBar --java-implement-android-os-parcelable true \
  --cpp-out "$work/$name/cpp" --cpp-namespace testsuite \
  --jni-use-on-load-initializer false --ident-jni-class NativeFooBar --ident-jni-file NativeFooBar \
  --idl djinni/kotlin_extern.djinni --idl-include-path djinni/vendor)
cp "$repo_root/ci/kotlin-jni/extern/kotlin_extern.djinni.kotlin.jni.h" "$work/$name/jni/"
if ! grep -q "com.dropbox.djinni.testextern.ExternKotlinMessage" "$work/$name/kotlin/KotlinExternRecord.kt" ||
   ! grep -q 'jniGetFieldID(clazz.get(), "mKeyed", "Lcom/dropbox/djinni/testextern/ExternKotlinMessage;")' "$work/$name/jni/NativeKotlinExternRecord.hpp"; then
  echo "FAIL: the Kotlin class and the JNI code of an extern record do not use the Kotlin class of the extern type" >&2
  exit 1
fi
compile_and_compare "$name" "$package" "$work/$name/yaml" "$repo_root/ci/kotlin-jni/extern" com.dropbox.djinni.testextern \
  "Lcom/dropbox/djinni/testextern/ExternJavaMessage;=Lcom/dropbox/djinni/testextern/ExternKotlinMessage;"
# The compare tool must reject a JNI lookup that it cannot parse, so a change in the shape of the generated C++
# cannot turn a lookup into a silent skip. The mutant has one lookup split over two lines.
mutant="$work/compare-mutant"
mkdir -p "$mutant"
cp -R "$work/suite/jni" "$mutant/jni"
python3 - "$mutant/jni" <<'PY'
import glob, sys
for path in sorted(glob.glob(sys.argv[1] + "/*")):
    text = open(path).read()
    if "jniGetFieldID(clazz.get(), " in text:
        open(path, "w").write(text.replace("jniGetFieldID(clazz.get(), ", "jniGetFieldID(\n    clazz.get(), ", 1))
        break
else:
    sys.exit("no jniGetFieldID lookup to mutate")
PY
if python3 "$repo_root/ci/kotlin_jni_compare.py" "$work/suite/java-classes" "$work/suite/kotlin-classes" "$mutant/jni" "$package" >"$mutant/out.log" 2>&1; then
  echo "FAIL: the compare tool accepted a JNI lookup that it cannot parse" >&2
  cat "$mutant/out.log" >&2
  exit 1
fi
if ! grep -qF "JNI lookups are not parsed" "$mutant/out.log"; then
  echo "FAIL: the compare tool failed for another reason than the unparsed lookup" >&2
  cat "$mutant/out.log" >&2
  exit 1
fi
echo "compare tool: an unparsed JNI lookup is rejected"

# A lookup with white space before the parenthesis is still a lookup: the tool must count it as the same one.
spaced="$work/compare-spaced"
mkdir -p "$spaced"
cp -R "$work/suite/jni" "$spaced/jni"
python3 - "$spaced/jni" <<'PY'
import glob, re, sys
changed = 0
for path in sorted(glob.glob(sys.argv[1] + "/*")):
    text = open(path).read()
    new = re.sub(r"\b(jni(?:GetFieldID|GetMethodID|GetStaticMethodID))\(", r"\1 (", text)
    if new != text:
        open(path, "w").write(new)
        changed += 1
if not changed:
    sys.exit("no lookup to change")
PY
plain_count="$(python3 "$repo_root/ci/kotlin_jni_compare.py" "$work/suite/java-classes" "$work/suite/kotlin-classes" "$work/suite/jni" "$package" | grep '^4\. JNI lookups')"
spaced_count="$(python3 "$repo_root/ci/kotlin_jni_compare.py" "$work/suite/java-classes" "$work/suite/kotlin-classes" "$spaced/jni" "$package" | grep '^4\. JNI lookups')"
if [ -z "$plain_count" ] || [ "$plain_count" != "$spaced_count" ]; then
  echo "FAIL: the compare tool counts a different number of lookups when there is white space before the parenthesis" >&2
  echo "plain:  $plain_count" >&2
  echo "spaced: $spaced_count" >&2
  exit 1
fi
echo "compare tool: a lookup with white space before the parenthesis is counted ($plain_count)"
echo "KOTLIN JNI CHECK OK"
