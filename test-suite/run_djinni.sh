#! /usr/bin/env bash
set -eu
shopt -s nullglob

# Locate the script file.  Cross symlinks if necessary.
loc="$0"
while [ -h "$loc" ]; do
    ls=`ls -ld "$loc"`
    link=`expr "$ls" : '.*-> \(.*\)$'`
    if expr "$link" : '/.*' > /dev/null; then
        loc="$link"  # Absolute link
    else
        loc="`dirname "$loc"`/$link"  # Relative link
    fi
done
base_dir=$(cd "`dirname "$loc"`" && pwd)

temp_out="$base_dir/djinni-output-temp"
in="$base_dir/djinni/all.djinni"
wchar_in="$base_dir/djinni/wchar_test.djinni"

# Relative version of in and temp_out are used for Djinni call below so that
# generated lists of infiles/outfiles are not machine-dependent.  This
# is an artifact of the test suite, where we want the genereated files
# to be in git for examination.
in_relative="djinni/all.djinni"
wchar_in_relative="djinni/wchar_test.djinni"
prologue_in_relative="djinni/function_prologue.djinni"
ident_explicit_in_relative="djinni/ident_explicit.djinni"
interface_and_abstract_class_in_relative="djinni/interface_and_abstract_class.djinni"
temp_out_relative="djinni-output-temp"

cpp_out="$base_dir/generated-src/cpp"
jni_out="$base_dir/generated-src/jni"
objc_out="$base_dir/generated-src/objc"
java_out="$base_dir/generated-src/java/com/dropbox/djinni/test"
wasm_out="$base_dir/generated-src/wasm"
ts_out="$base_dir/generated-src/ts"
kotlin_out="$base_dir/generated-src/kotlin"
yaml_out="$base_dir/generated-src/yaml"

java_package="com.dropbox.djinni.test"
kotlin_package="com.dropbox.djinni.test.interop"

gen_stamp="$temp_out/gen.stamp"

if [ $# -eq 0 ]; then
    # Normal build.
    true
elif [ $# -eq 1 ]; then
    command="$1"; shift
    if [ "$command" != "clean" ]; then
        echo "Unexpected arguemnt: \"$command\"." 1>&2
        exit 1
    fi
    for dir in "$temp_out" "$cpp_out" "$jni_out" "$java_out" "$kotlin_out"; do
        if [ -e "$dir" ]; then
            echo "Deleting \"$dir\"..."
            rm -r "$dir"
        fi
    done
    rm "$base_dir/generated-src/inFileList.txt"
    rm "$base_dir/generated-src/outFileList.txt"
    exit
fi

# Build Djinni
"$base_dir/../src/build.sh"

# Run Djinni generation
[ ! -e "$temp_out" ] || rm -r "$temp_out"
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    --cpp-use-wide-strings true \
    \
    --jni-out "$temp_out_relative/jni" \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --wasm-out "$temp_out_relative/wasm" \
    --wasm-namespace "testsuite" \
    --ts-out "$temp_out_relative/ts" \
    --ts-module "test_wchar" \
    \
    --yaml-out "$temp_out_relative/yaml" \
    --yaml-out-file "yaml-test.yaml" \
    --yaml-prefix "test_" \
    \
    --idl "$wchar_in_relative" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --java-implement-android-os-parcelable true \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    \
    --jni-out "$temp_out_relative/jni" \
    --jni-use-on-load-initializer false \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --wasm-out "$temp_out_relative/wasm" \
    --wasm-namespace "testsuite" \
    --ts-out "$temp_out_relative/ts" \
    --ts-module "test" \
    \
    --list-in-files "./generated-src/inFileList.txt" \
    --list-out-files "./generated-src/outFileList.txt"\
    \
    --yaml-out "$temp_out_relative/yaml" \
    --yaml-out-file "yaml-test.yaml" \
    --yaml-prefix "test_" \
    \
    --idl "$in_relative" \
    --idl-include-path "djinni/vendor" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    \
    --jni-out "$temp_out_relative/jni" \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    --jni-function-prologue-file "../../handwritten-src/cpp/jni_prologue.hpp" \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    --objcpp-function-prologue-file "../../handwritten-src/cpp/objcpp-prologue.hpp" \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --idl "$prologue_in_relative" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --ident-java-type NativeFooBar! \
    --ident-java-field mFooBar! \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-file foo_bar! \
    --ident-cpp-enum-type foo_bar! \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    \
    --jni-out "$temp_out_relative/jni" \
    --ident-jni-file NativeFooBar! \
    --ident-jni-class NativeFooBar! \
    --jni-function-prologue-file "../../handwritten-src/cpp/jni_prologue.hpp" \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    --objcpp-function-prologue-file "../../handwritten-src/cpp/objcpp-prologue.hpp" \
    --ident-objc-type FooBar! \
    --ident-objc-enum NativeFooBar! \
    --ident-objc-const NativeFooBar! \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --idl "$ident_explicit_in_relative" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --java-implement-android-os-parcelable true \
    --java-gen-interface true \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    --cpp-extended-record-include-prefix "../../handwritten-src/cpp/" \
    \
    --jni-out "$temp_out_relative/jni" \
    --jni-use-on-load-initializer false \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --yaml-out "$temp_out_relative/yaml" \
    --yaml-out-file "yaml-interface-test.yaml" \
    --yaml-prefix "test_" \
    \
    --idl "$interface_and_abstract_class_in_relative" \
    --idl-include-path "djinni/vendor" \
)

# Make sure we can parse back our own generated YAML file
cp "$base_dir/djinni/yaml-test.djinni" "$temp_out/yaml"
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/java" \
    --java-package $java_package \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/cpp" \
    --ident-cpp-enum-type foo_bar \
    --cpp-optional-template "std::experimental::optional" \
    --cpp-optional-header "\"../../handwritten-src/cpp/optional.hpp\"" \
    \
    --jni-out "$temp_out_relative/jni" \
    --jni-use-on-load-initializer false \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$temp_out_relative/objc" \
    --objcpp-out "$temp_out_relative/objc" \
    --objc-type-prefix DB \
    \
    --wasm-out "$temp_out_relative/wasm" \
    --wasm-namespace "testsuite" \
    --ts-out "$temp_out_relative/ts" \
    --ts-module "test_yaml" \
    \
    --kotlin-out "$temp_out_relative/kotlin" \
    --kotlin-package $kotlin_package \
    --kotlin-support-package "com.safetyculture.djinni.support" \
    --kotlin-cinterop-package "TestSuite" \
    \
    --idl "$temp_out_relative/yaml/yaml-test.djinni" \
)

# Swift cases. They have their own output tree because the other test targets compile the main trees.
swift_host_relative="djinni/swift_host.djinni"
swift_idents_relative="djinni/swift_idents.djinni"
swift_types_relative="djinni/swift_types.djinni"
swift_sendable_relative="djinni/swift_sendable.djinni"
swift_legacy_relative="djinni/swift_legacy.djinni"
swift_future_field_relative="djinni/swift_future_field.djinni"
swift_async_relative="djinni/swift_async.djinni"
swift_error_relative="djinni/swift_error.djinni"
swift_error_negative_relative="djinni/swift_error_negative.djinni"
swift_error_enum_relative="djinni/swift_error_enum.djinni"
swift_error_extern_relative="djinni/swift_error_extern.djinni"
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/swift-features/host/java" \
    --java-package $java_package \
    --ident-java-field mFooBar \
    \
    --cpp-out "$temp_out_relative/swift-features/host/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --jni-out "$temp_out_relative/swift-features/host/jni" \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$temp_out_relative/swift-features/host/objc" \
    --objcpp-out "$temp_out_relative/swift-features/host/objc" \
    --objc-type-prefix DB \
    \
    --swift-out "$temp_out_relative/swift-features/host/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/host/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_host_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/idents/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/idents/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/idents/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_idents_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/types/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/types/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/types/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_types_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/sendable/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/sendable/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/sendable/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_sendable_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/legacy/cpp" \
    --cpp-namespace testsuite \
    \
    --swift-out "$temp_out_relative/swift-features/legacy/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-legacy-records \
    --swiftxx-out "$temp_out_relative/swift-features/legacy/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_legacy_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/future-field/cpp" \
    --cpp-namespace testsuite \
    \
    --swift-out "$temp_out_relative/swift-features/future-field/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    \
    --idl "$swift_future_field_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/async/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/async/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-async-wrap "djinni.testsuite" \
    --swiftxx-out "$temp_out_relative/swift-features/async/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_async_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/error/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/error/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-async-wrap "djinni.testsuite" \
    --swift-error-type CruxError \
    --swiftxx-out "$temp_out_relative/swift-features/error/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_error_relative" \
)

# A protobuf message without a swift block must fail the run before any file is written.
swift_protobuf_negative_relative="djinni/swift_protobuf_negative.djinni"
for swift_flag in --swift-out --swiftxx-out; do
    protobuf_negative_out="$temp_out/swift-protobuf-negative-${swift_flag#--}"
    rm -rf "$protobuf_negative_out"
    set +e
    (cd "$base_dir" && \
    "$base_dir/../src/run-assume-built" \
        --cpp-out "$protobuf_negative_out/cpp" \
        --cpp-namespace testsuite \
        "$swift_flag" "$protobuf_negative_out/swift" \
        --swift-module TestSuite \
        --idl "$swift_protobuf_negative_relative") > "$protobuf_negative_out.log" 2>&1
    negative_status=$?
    set -e
    if [ "$negative_status" -ne 1 ] || \
       ! grep -q "Protobuf message Person has no 'swift' block in its manifest, but Swift output is enabled." "$protobuf_negative_out.log" || \
       [ -e "$protobuf_negative_out" ]; then
        echo "The generator accepted a protobuf message without a swift block, or wrote files ($swift_flag, exit $negative_status)." 1>&2
        cat "$protobuf_negative_out.log" 1>&2
        exit 1
    fi
    rm -f "$protobuf_negative_out.log"
done

# The generator must reject methods without outcome<> and write no file.
negative_out="$temp_out_relative/swift-features/error-negative"
negative_log="$temp_out/error-negative.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --cpp-out "$negative_out/cpp" \
    --cpp-namespace testsuite \
    --swift-out "$negative_out/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-error-type CruxError \
    --idl "$swift_error_negative_relative") >"$negative_log" 2>&1; then
    echo "The generator accepted $swift_error_negative_relative with --swift-error-type." 1>&2
    exit 1
fi
for expected in \
    "interface swift_error_bad_service, method plain: --swift-error-type needs a return type outcome<T, CruxError>" \
    "interface swift_error_bad_service, method nothing: --swift-error-type needs a return type outcome<T, CruxError>" \
    "interface swift_error_bad_service, method wrong_error: the error type of the outcome is OtherError, but --swift-error-type is CruxError" \
    "interface swift_error_bad_service, method load: --swift-error-type needs a return type outcome<T, CruxError>" \
    "interface swift_error_bad_shared, method value: --swift-error-type needs a return type outcome<T, CruxError>"; do
    if ! grep -qF "$expected" "$negative_log"; then
        echo "Missing error message: $expected" 1>&2
        cat "$negative_log" 1>&2
        exit 1
    fi
done
if grep -qE "method (fine|on_value)" "$negative_log"; then
    echo "The generator reported a method that follows the rule." 1>&2
    exit 1
fi
if [ -e "$base_dir/$negative_out" ]; then
    echo "The generator wrote files for a rejected IDL." 1>&2
    exit 1
fi

# The name of the flag must match a record, and the record must be a record.
expect_failure() { # <log name> <idl> <flag value> <expected message>...
    local log="$temp_out/$1.log" idl="$2" name="$3" expected
    shift 3
    if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
        --swift-out "$temp_out_relative/swift-features/$1/swift" \
        --swift-module TestSuite \
        --swift-private-in-same-module \
        --swift-error-type "$name" \
        --idl-include-path "djinni/vendor" \
        --idl "$idl") >"$log" 2>&1; then
        echo "The generator accepted $idl with --swift-error-type $name." 1>&2
        exit 1
    fi
    for expected in "$@"; do
        if ! grep -qF -- "$expected" "$log"; then
            echo "Missing error message: $expected" 1>&2
            cat "$log" 1>&2
            exit 1
        fi
    done
    if [ -e "$base_dir/$temp_out_relative/swift-features/$1" ]; then
        echo "The generator wrote files for a rejected IDL." 1>&2
        exit 1
    fi
}
expect_failure error-renamed "$swift_error_relative" Renamed \
    "--swift-error-type Renamed: no record has this Swift name" \
    "interface swift_error_service, method fetch: the error type of the outcome is CruxError, but --swift-error-type is Renamed"
expect_failure error-enum "$swift_error_enum_relative" CruxError \
    "interface swift_error_enum_service, method f: the error type CruxError is not a record"

# An extern record with the Swift name is accepted.
(cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --swift-out "$temp_out_relative/error-extern/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-error-type CruxError \
    --idl-include-path "djinni/vendor" \
    --idl "$swift_error_extern_relative") >"$temp_out/error-extern.log" 2>&1 || {
    echo "The generator rejected an extern error record." 1>&2
    cat "$temp_out/error-extern.log" 1>&2
    exit 1
}

# Kotlin classes for the JNI code. The Kotlin JNI check compiles them with the Java classes of the same IDL.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --java-use-final-for-record false \
    --java-implement-android-os-parcelable true \
    --java-gen-interface true \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_jni.djinni" \
    --idl-include-path "djinni/vendor" \
)

# Kotlin suspend functions for the interfaces that C++ implements.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-suspend" \
    --kotlin-suspend-wrap \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_suspend.djinni" \
)

# Copy changes from "$temp_out" to final dir.

mirror() {
    local prefix="$1" ; shift
    local src="$1" ; shift
    local dest="$1" ; shift
    mkdir -p "$dest"
    rsync -r --delete --checksum --itemize-changes "$src"/ "$dest" | sed "s/^/[$prefix]/"
}

echo "Copying generated code to final directories..."
mirror "cpp" "$temp_out/cpp" "$cpp_out"
mirror "java" "$temp_out/java" "$java_out"
mirror "jni" "$temp_out/jni" "$jni_out"
mirror "objc" "$temp_out/objc" "$objc_out"
mirror "kotlin" "$temp_out/kotlin" "$kotlin_out"
mirror "wasm" "$temp_out/wasm" "$wasm_out"
mirror "ts" "$temp_out/ts" "$ts_out"
mirror "swift-features" "$temp_out/swift-features" "$base_dir/generated-src/swift-features"
mirror "kotlin-jni" "$temp_out/kotlin-jni" "$base_dir/generated-src/kotlin-jni"
mirror "kotlin-jni-suspend" "$temp_out/kotlin-jni-suspend" "$base_dir/generated-src/kotlin-jni-suspend"

date > "$gen_stamp"

echo "Djinni completed."
