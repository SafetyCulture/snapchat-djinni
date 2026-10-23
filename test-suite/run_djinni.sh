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
swift_options_relative="djinni/swift_options.djinni"
swift_result_name_relative="djinni/swift_result_name.djinni"
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
    --idl "$swift_host_relative"
) >"$temp_out/swift-host.log" 2>&1 || { cat "$temp_out/swift-host.log" 1>&2; exit 1; }
cat "$temp_out/swift-host.log"
# An interface with +o but not +sw gets no Swift proxy, and the generator says so once.
if [ "$(grep -cF -- "Warning: interface objc_host_listener has +o but not +sw. The generator makes no Swift proxy for it." "$temp_out/swift-host.log")" -ne 1 ] || \
   [ "$(grep -c "^Warning: interface .* has +o but not +sw" "$temp_out/swift-host.log")" -ne 1 ]; then
    echo "Missing, repeated or extra warning for an interface with +o but not +sw." 1>&2
    cat "$temp_out/swift-host.log" 1>&2
    exit 1
fi
(cd "$base_dir" && \
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
    --idl "$swift_error_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/options/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/options/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/options/swiftxx" \
    --swiftxx-namespace djinni_options \
    --swiftxx-include-prefix "options/" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    --swiftxx-base-lib-module OptionsSupport \
    --swiftxx-base-lib-include-prefix "support/" \
    \
    --idl "$swift_options_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/separate-module/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/separate-module/swift" \
    --swift-module TestSuite \
    --swiftxx-out "$temp_out_relative/swift-features/separate-module/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_types_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/error-legacy/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/error-legacy/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-legacy-records \
    --swift-async-wrap "djinni.testsuite" \
    --swift-async-queue "DispatchQueue.global(qos: .utility)" \
    --swift-error-type CruxError \
    --swiftxx-out "$temp_out_relative/swift-features/error-legacy/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_error_relative" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/result-name/cpp" \
    --cpp-namespace testsuite \
    --ident-cpp-enum-type foo_bar \
    \
    --swift-out "$temp_out_relative/swift-features/result-name/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-async-wrap "djinni.testsuite" \
    --swiftxx-out "$temp_out_relative/swift-features/result-name/swiftxx" \
    --swiftxx-include-cpp-prefix "../cpp/" \
    \
    --idl "$swift_result_name_relative" \
)
# Every +Private.swift file of the options case must import the base library module.
options_private=("$temp_out"/swift-features/options/swift/*+Private.swift)
if [ "${#options_private[@]}" -eq 0 ]; then
    options_missing="there is no +Private.swift file"
else
    options_missing="$(grep -L -x "import OptionsSupport" "${options_private[@]}" || true)"
fi
if [ -n "$options_missing" ]; then
    echo "The options case does not import --swiftxx-base-lib-module in: $options_missing" 1>&2
    exit 1
fi

# A nested --swiftxx-namespace is valid C++ and the generated Swift calls it with dots.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swift-features/nested-ns/cpp" \
    --cpp-namespace testsuite \
    \
    --swift-out "$temp_out_relative/swift-features/nested-ns/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swiftxx-out "$temp_out_relative/swift-features/nested-ns/swiftxx" \
    --swiftxx-namespace "djinni_options::nested" \
    \
    --idl "$swift_options_relative" \
)
if ! grep -qx "namespace djinni_options::nested {" "$temp_out"/swift-features/nested-ns/swiftxx/*.hpp; then
    echo "The nested-namespace case does not write the C++ namespace." 1>&2
    exit 1
fi
if ! grep -q "djinni_options\.nested\." "$temp_out"/swift-features/nested-ns/swift/*+Private.swift; then
    echo "The nested-namespace case does not call the namespace with dots in Swift." 1>&2
    exit 1
fi
# The interface constant of the options case is on the _statics class.
if ! grep -qF "static let maxCount" "$temp_out"/swift-features/options/swift/SwiftOptionsService+Private.swift; then
    echo "The interface constant is not on the _statics class." 1>&2
    exit 1
fi
# A DataRef or a DataView makes a record not Sendable, also inside a container, an outcome or another record.
# There is no @unchecked claim for it. A record without them stays Sendable.
for name in WithData WithOptionalData WithViewList WithDataMap WithOutcomeData Outer; do
    sendable_file="$temp_out/swift-features/sendable/swift/SwiftSendable$name.swift"
    if grep -qE "^public struct SwiftSendable$name\b.*Sendable" "$sendable_file" || grep -q "@unchecked" "$sendable_file"; then
        echo "SwiftSendable$name holds a DataRef or a DataView, but its record claims Sendable." 1>&2
        grep -nE "^public struct|@unchecked" "$sendable_file" 1>&2
        exit 1
    fi
done
for name in Plain Nested WithOutcome; do
    sendable_file="$temp_out/swift-features/sendable/swift/SwiftSendable$name.swift"
    if ! grep -qE "^public struct SwiftSendable$name: .*\bSendable\b" "$sendable_file" || grep -q "@unchecked" "$sendable_file"; then
        echo "SwiftSendable$name must be Sendable without @unchecked." 1>&2
        exit 1
    fi
done

# A label prefix that would break the generated string literal is rejected.
prefix_log="$temp_out/swift-async-wrap-prefix.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --swift-out "$temp_out_relative/swift-async-wrap-prefix/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-async-wrap 'bad"prefix' \
    --idl "$swift_async_relative") >"$prefix_log" 2>&1; then
    echo "The generator accepted a --swift-async-wrap prefix with a quote." 1>&2
    exit 1
fi
if ! grep -qF -- "--swift-async-wrap accepts only letters, digits, dot, underscore and hyphen." "$prefix_log"; then
    echo "Missing error message for a bad --swift-async-wrap prefix." 1>&2
    cat "$prefix_log" 1>&2
    exit 1
fi

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

# An extern yaml without the swift/swiftxx blocks must fail the run before any file is written.
swift_extern_negative_relative="djinni/swift_extern_negative.djinni"
for swift_flag in --swift-out --swiftxx-out; do
    extern_negative_out="$temp_out/swift-extern-negative-${swift_flag#--}"
    rm -rf "$extern_negative_out"
    set +e
    (cd "$base_dir" && \
    "$base_dir/../src/run-assume-built" \
        --cpp-out "$extern_negative_out/cpp" \
        --cpp-namespace testsuite \
        "$swift_flag" "$extern_negative_out/swift" \
        --swift-module TestSuite \
        --idl "$swift_extern_negative_relative") > "$extern_negative_out.log" 2>&1
    extern_negative_status=$?
    set -e
    if [ "$extern_negative_status" -ne 1 ] || \
       ! grep -q "Extern type extern_no_swift has no 'swift'/'swiftxx' blocks in its manifest, but Swift output is enabled." "$extern_negative_out.log" || \
       [ -e "$extern_negative_out" ]; then
        echo "The generator accepted an extern yaml without swift blocks, or wrote files ($swift_flag, exit $extern_negative_status)." 1>&2
        cat "$extern_negative_out.log" 1>&2
        exit 1
    fi
    rm -f "$extern_negative_out.log"
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
    "interface swift_error_bad_service, method future_outcome: --swift-error-type does not support a return type future<outcome<T, CruxError>>" \
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
    --swift-out "$temp_out_relative/swift-features/error-extern/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-error-type CruxError \
    --idl-include-path "djinni/vendor" \
    --idl "$swift_error_extern_relative") >"$temp_out/error-extern.log" 2>&1 || {
    echo "The generator rejected an extern error record." 1>&2
    cat "$temp_out/error-extern.log" 1>&2
    exit 1
}

# The flag for suspend functions needs the Kotlin JNI output.
suspend_log="$temp_out/suspend-without-out.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-suspend-wrap \
    --java-package $java_package \
    --idl "djinni/kotlin_suspend.djinni") >"$suspend_log" 2>&1; then
    echo "The generator accepted --kotlin-suspend-wrap without --kotlin-jni-out." 1>&2
    exit 1
fi
if ! grep -qF -- "Error: --kotlin-suspend-wrap needs --kotlin-jni-out." "$suspend_log"; then
    echo "Missing error message for --kotlin-suspend-wrap." 1>&2
    cat "$suspend_log" 1>&2
    exit 1
fi

# The dispatcher flag needs the suspend functions.
dispatcher_log="$temp_out/dispatcher-without-suspend.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-dispatcher" \
    --kotlin-suspend-dispatcher "Dispatchers.Default" \
    --java-package $java_package \
    --idl "djinni/kotlin_suspend.djinni") >"$dispatcher_log" 2>&1; then
    echo "The generator accepted --kotlin-suspend-dispatcher without --kotlin-suspend-wrap." 1>&2
    exit 1
fi
if ! grep -qF -- "Error: --kotlin-suspend-dispatcher needs --kotlin-suspend-wrap." "$dispatcher_log"; then
    echo "Missing error message for --kotlin-suspend-dispatcher." 1>&2
    cat "$dispatcher_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/kotlin-jni-dispatcher" ]; then
    echo "The generator wrote files for a rejected flag." 1>&2
    exit 1
fi

# The error type flag needs the Kotlin JNI output.
error_type_log="$temp_out/kotlin-error-type-without-out.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-error-type "com.dropbox.djinni.test.KotlinErrorException" \
    --java-package $java_package \
    --idl "djinni/kotlin_error.djinni") >"$error_type_log" 2>&1; then
    echo "The generator accepted --kotlin-error-type without --kotlin-jni-out." 1>&2
    exit 1
fi
if ! grep -qF -- "Error: --kotlin-error-type needs --kotlin-jni-out." "$error_type_log"; then
    echo "Missing error message for --kotlin-error-type." 1>&2
    cat "$error_type_log" 1>&2
    exit 1
fi

# kotlin_expect_failure <log name> <idl> <expected message>... : --kotlin-error-type rejects the IDL before it writes a file.
kotlin_expect_failure() {
    local name=$1 idl=$2
    shift 2
    local log="$temp_out/$name.log"
    if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
        --kotlin-jni-out "$temp_out_relative/$name" \
        --kotlin-error-type "com.dropbox.djinni.test.KotlinErrorException" \
        --java-package $java_package \
        --idl "$idl") >"$log" 2>&1; then
        echo "The generator accepted $idl with --kotlin-error-type." 1>&2
        exit 1
    fi
    for expected in "$@"; do
        if ! grep -qF -- "$expected" "$log"; then
            echo "Missing error message: $expected" 1>&2
            cat "$log" 1>&2
            exit 1
        fi
    done
    if [ -e "$base_dir/$temp_out_relative/$name" ]; then
        echo "The generator wrote files for $idl with --kotlin-error-type." 1>&2
        exit 1
    fi
}
# A future needs a suspend function, for an instance method and for a static method.
kotlin_expect_failure kotlin-error-future "djinni/kotlin_error_async.djinni" \
    "interface kotlin_error_async_service, method load: --kotlin-error-type needs --kotlin-suspend-wrap for a method that returns future<T>" \
    "interface kotlin_error_async_service, method fetch_later: --kotlin-error-type needs --kotlin-suspend-wrap for a method that returns future<T>" \
    "interface kotlin_error_async_service, method load_static: --kotlin-error-type needs --kotlin-suspend-wrap for a method that returns future<T>"
# The class has one constructor (error: E), so the outcomes must have one error type.
kotlin_expect_failure kotlin-error-mixed "djinni/kotlin_error_negative.djinni" \
    "--kotlin-error-type com.dropbox.djinni.test.KotlinErrorException has one constructor (error: E), but the outcomes have 2 error types: KotlinErrorFirst (interface kotlin_error_mixed, method first), KotlinErrorSecond (interface kotlin_error_mixed, method second)"

# The queue flag needs the async wrappers.
queue_log="$temp_out/queue-without-wrap.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --swift-out "$temp_out_relative/swift-features/queue-without-wrap/swift" \
    --swift-module TestSuite \
    --swift-private-in-same-module \
    --swift-async-queue "DispatchQueue.main" \
    --idl "$swift_async_relative") >"$queue_log" 2>&1; then
    echo "The generator accepted --swift-async-queue without --swift-async-wrap." 1>&2
    exit 1
fi
if ! grep -qF -- "Error: --swift-async-queue needs --swift-async-wrap." "$queue_log"; then
    echo "Missing error message for --swift-async-queue." 1>&2
    cat "$queue_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/swift-features/queue-without-wrap" ]; then
    echo "The generator wrote files for a rejected flag." 1>&2
    exit 1
fi

# The async wrappers need the private files in the same module.
async_log="$temp_out/async-without-module.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --swift-out "$temp_out_relative/swift-features/async-without-module/swift" \
    --swift-module TestSuite \
    --swift-async-wrap "djinni.testsuite" \
    --idl "$swift_async_relative") >"$async_log" 2>&1; then
    echo "The generator accepted --swift-async-wrap without --swift-private-in-same-module." 1>&2
    exit 1
fi
if ! grep -qF -- "Error: --swift-async-wrap needs --swift-private-in-same-module." "$async_log"; then
    echo "Missing error message for --swift-async-wrap." 1>&2
    cat "$async_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/swift-features/async-without-module" ]; then
    echo "The generator wrote files for a rejected flag." 1>&2
    exit 1
fi

# The Swift glue and the Objective-C++ glue define the same helper symbols when they share a namespace.
# The default namespaces differ. Equal namespaces fail the run before any file is written.
namespace_out="$temp_out/swiftxx-namespace-equal"
namespace_log="$namespace_out.log"
rm -rf "$namespace_out"
set +e
(cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --cpp-out "$temp_out_relative/swiftxx-namespace-equal/cpp" \
    --cpp-namespace testsuite \
    --objcpp-out "$temp_out_relative/swiftxx-namespace-equal/objc" \
    --objc-type-prefix DB \
    --swiftxx-out "$temp_out_relative/swiftxx-namespace-equal/swiftxx" \
    --swiftxx-namespace djinni_generated \
    --swift-out "$temp_out_relative/swiftxx-namespace-equal/swift" \
    --swift-module TestSuite \
    --idl "$swift_types_relative") >"$namespace_log" 2>&1
namespace_status=$?
set -e
if [ "$namespace_status" -ne 1 ] || \
   ! grep -qF -- 'Error: --swiftxx-namespace and --objcpp-namespace are both "djinni_generated".' "$namespace_log" || \
   [ -e "$namespace_out" ]; then
    echo "The generator accepted equal --swiftxx-namespace and --objcpp-namespace, or wrote files (exit $namespace_status)." 1>&2
    cat "$namespace_log" 1>&2
    exit 1
fi
rm -f "$namespace_log"

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

# The error type of the application: blocking functions, and suspend functions for the futures.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-error/sync" \
    --kotlin-error-type "com.dropbox.djinni.test.KotlinErrorException" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_error.djinni" \
)
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-error/suspend" \
    --kotlin-suspend-wrap \
    --kotlin-error-type "com.dropbox.djinni.test.KotlinErrorException" \
    --java-package $java_package \
    --java-nullable-annotation "javax.annotation.CheckForNull" \
    --java-nonnull-annotation "javax.annotation.Nonnull" \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_error_async.djinni" \
)

# Kotlin classes in a package other than the Java package, with the dispatcher of the application.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-package" \
    --kotlin-jni-package "com.dropbox.djinni.test.kt" \
    --kotlin-suspend-wrap \
    --kotlin-suspend-dispatcher "com.dropbox.djinni.test.kt.TestDispatchers.blocking" \
    --java-package $java_package \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_suspend.djinni" \
)
if grep -L "^package com.dropbox.djinni.test.kt$" "$temp_out"/kotlin-jni-package/*.kt | grep -q .; then
    echo "A Kotlin file has a package other than --kotlin-jni-package." 1>&2
    exit 1
fi

# An extern record with the Kotlin keys: the Kotlin classes and the JNI code use its Kotlin class.
# The second run has no --kotlin-jni-out: the JNI code uses the Java class.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-extern/jni" \
    --java-package $java_package \
    --java-implement-android-os-parcelable true \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_extern.djinni" \
    --idl-include-path "djinni/vendor" \
)
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --jni-out "$temp_out_relative/kotlin-jni-extern/jni-java" \
    --java-package $java_package \
    --ident-java-field mFooBar \
    --jni-use-on-load-initializer false \
    --idl "djinni/kotlin_extern.djinni" \
    --idl-include-path "djinni/vendor" \
)

# An extern type may carry the name of a Parceler; it writes no Kotlin file, so it cannot collide.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-parceler-name/kotlin" \
    --java-package $java_package \
    --java-implement-android-os-parcelable true \
    --idl "djinni/kotlin_extern_parceler_name.djinni" \
    --idl-include-path "djinni/vendor" \
)

# An internal record with the name of the Parceler of an extern type is rejected before any file is written.
parceler_collision_log="$temp_out/kotlin-jni-extern-parceler-collision.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-parceler-collision/kotlin" \
    --java-package $java_package \
    --java-implement-android-os-parcelable true \
    --idl "djinni/kotlin_extern_parceler_collision.djinni" \
    --idl-include-path "djinni/vendor") >"$parceler_collision_log" 2>&1; then
    echo "The generator accepted an IDL type with the name of a Parceler." 1>&2
    exit 1
fi
if ! grep -qF -- "The Parceler name ExternKotlinMessageParceler collides with an IDL type of the same name." "$parceler_collision_log"; then
    echo "Missing error message for a Parceler name collision." 1>&2
    cat "$parceler_collision_log" 1>&2
    exit 1
fi

# array<extern> with a Java primitive is a primitive array; with a Kotlin key it is Array<T>.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-array/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-extern-array/jni" \
    --java-package $java_package \
    --idl "djinni/kotlin_extern_array.djinni" \
    --idl-include-path "djinni/vendor" \
)
if ! grep -qF -- "val bytes: ByteArray" "$temp_out"/kotlin-jni-extern-array/kotlin/KotlinExternArrays.kt || \
   ! grep -qF -- "val keyed: Array<com.dropbox.djinni.testextern.ExternByteMessage>" "$temp_out"/kotlin-jni-extern-array/kotlin/KotlinExternArrays.kt; then
    echo "The array<extern> case does not produce a primitive array and an Array<T>." 1>&2
    exit 1
fi

# With --jni-out, --kotlin-jni-package must equal --java-package.
(cd "$base_dir" && \
"$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-package-equal/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-package-equal/jni" \
    --kotlin-jni-package "$java_package" \
    --java-package $java_package \
    --idl "djinni/kotlin_suspend.djinni" \
)
pkg_log="$temp_out/kotlin-jni-package-mismatch.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-package-mismatch/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-package-mismatch/jni" \
    --kotlin-jni-package "com.dropbox.djinni.test.other" \
    --java-package $java_package \
    --idl "djinni/kotlin_suspend.djinni") >"$pkg_log" 2>&1; then
    echo "The generator accepted --kotlin-jni-package that differs from --java-package with --jni-out." 1>&2
    exit 1
fi
if ! grep -qF -- "--kotlin-jni-package must equal --java-package when the JNI code binds the classes." "$pkg_log"; then
    echo "Missing error message for a package mismatch." 1>&2
    cat "$pkg_log" 1>&2
    exit 1
fi

# The JNI code binds one class for an extern record, so it cannot serve --java-out and --kotlin-jni-out.
extern_log="$temp_out/kotlin-jni-extern-both.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --java-out "$temp_out_relative/kotlin-jni-extern-both/java" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-both/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-extern-both/jni" \
    --java-package $java_package \
    --idl "djinni/kotlin_extern.djinni" \
    --idl-include-path "djinni/vendor") >"$extern_log" 2>&1; then
    echo "The generator accepted --java-out and --kotlin-jni-out with an extern record that has Kotlin keys." 1>&2
    exit 1
fi
if ! grep -qF -- "bind one class for each extern type" "$extern_log"; then
    echo "Missing error message for --java-out and --kotlin-jni-out with Kotlin keys." 1>&2
    cat "$extern_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/kotlin-jni-extern-both" ]; then
    echo "The generator wrote files for a rejected flag combination." 1>&2
    exit 1
fi

# Two Kotlin classes with one simple name need two Parcelers with one name. The generator must report it before
# it writes a file.
parceler_log="$temp_out/kotlin-jni-extern-parceler.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-parceler/kotlin" \
    --java-package $java_package \
    --java-implement-android-os-parcelable true \
    --idl "djinni/kotlin_extern_clash.djinni" \
    --idl-include-path "djinni/vendor") >"$parceler_log" 2>&1; then
    echo "The generator accepted two Kotlin classes that need a Parceler with the same name." 1>&2
    exit 1
fi
if ! grep -qF -- "The classes com.dropbox.djinni.testextern.ExternKotlinMessage and com.dropbox.djinni.testextern.other.ExternKotlinMessage need a Parceler with the same name ExternKotlinMessageParceler." "$parceler_log"; then
    echo "Missing error message for two Parcelers with one name." 1>&2
    cat "$parceler_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/kotlin-jni-extern-parceler" ]; then
    echo "The generator wrote files for two Parcelers with one name." 1>&2
    exit 1
fi

# An extern type with only some of the Kotlin keys is rejected before any file is written.
partial_log="$temp_out/kotlin-jni-extern-partial.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-partial/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-extern-partial/jni" \
    --java-package $java_package \
    --idl "djinni/kotlin_extern_partial.djinni" \
    --idl-include-path "djinni/vendor") >"$partial_log" 2>&1; then
    echo "The generator accepted an extern type with a partial set of Kotlin keys." 1>&2
    exit 1
fi
if ! grep -qF -- "Set all four Kotlin keys or none." "$partial_log"; then
    echo "Missing error message for a partial set of Kotlin keys." 1>&2
    cat "$partial_log" 1>&2
    exit 1
fi

# The JNI signature and the Kotlin class of an extern type must name one class.
mismatch_log="$temp_out/kotlin-jni-extern-mismatch.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-mismatch/kotlin" \
    --jni-out "$temp_out_relative/kotlin-jni-extern-mismatch/jni" \
    --java-package $java_package \
    --idl "djinni/kotlin_extern_mismatch.djinni" \
    --idl-include-path "djinni/vendor") >"$mismatch_log" 2>&1; then
    echo "The generator accepted an extern type whose Kotlin signature and Kotlin class differ." 1>&2
    exit 1
fi
if ! grep -qF -- "extern type extern_kotlin_mismatch: jni.kotlinTypeSignature Lcom/dropbox/djinni/testextern/Other; names the class com.dropbox.djinni.testextern.Other, but kotlin.jniTypename is com.dropbox.djinni.testextern.Partial." "$mismatch_log"; then
    echo "Missing error message for a Kotlin signature that differs from the Kotlin class." 1>&2
    cat "$mismatch_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/kotlin-jni-extern-mismatch" ]; then
    echo "The generator wrote files for a Kotlin signature that differs from the Kotlin class." 1>&2
    exit 1
fi

# A record cannot derive ord over the Kotlin class of an extern type with Kotlin keys: a message has no order.
ord_log="$temp_out/kotlin-jni-extern-ord.log"
if (cd "$base_dir" && "$base_dir/../src/run-assume-built" \
    --kotlin-jni-out "$temp_out_relative/kotlin-jni-extern-ord/kotlin" \
    --java-package $java_package \
    --idl "djinni/kotlin_extern_ord_negative.djinni" \
    --idl-include-path "djinni/vendor") >"$ord_log" 2>&1; then
    echo "The generator accepted deriving(ord) over the Kotlin class of an extern type." 1>&2
    exit 1
fi
if ! grep -qF -- "record kotlin_extern_ord_bad_record, field keyed: deriving(ord) needs a Comparable class, but the Kotlin class com.dropbox.djinni.testextern.ExternKotlinMessage of an extern type has no order." "$ord_log" || \
   grep -qF -- "kotlin_extern_ord_plain_record" "$ord_log"; then
    echo "Missing or wrong error message for deriving(ord) over the Kotlin class of an extern type." 1>&2
    cat "$ord_log" 1>&2
    exit 1
fi
if [ -e "$base_dir/$temp_out_relative/kotlin-jni-extern-ord" ]; then
    echo "The generator wrote files for deriving(ord) over the Kotlin class of an extern type." 1>&2
    exit 1
fi

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
mirror "kotlin-jni-package" "$temp_out/kotlin-jni-package" "$base_dir/generated-src/kotlin-jni-package"
mirror "kotlin-jni-error" "$temp_out/kotlin-jni-error" "$base_dir/generated-src/kotlin-jni-error"
mirror "kotlin-jni-extern" "$temp_out/kotlin-jni-extern" "$base_dir/generated-src/kotlin-jni-extern"

date > "$gen_stamp"

echo "Djinni completed."
