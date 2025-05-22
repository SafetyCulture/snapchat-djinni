#! /usr/bin/env bash
set -eu

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

in="$base_dir/djinni/main.djinni"
out="$base_dir/generated"

cpp_out="$out/cpp"
jni_out="$out/jni"
objc_out="$out/objc"
java_out="$out/java/com/safetyculture/krux/domain"
kotlin_out="$out/kotlin"

java_package="com.safetyculture.krux.domain"
kotlin_package="com.safetyculture.krux.domain"
kotlin_support_package="com.safetyculture.djinnisupport"
kotlin_cinterop_package="Crux"

# Build djinni
"$base_dir/../src/build.sh"

[ ! -e "$out" ] || rm -r "$out"
"$base_dir/../src/run-assume-built" \
    --java-out "$java_out" \
    --java-package $java_package \
    --java-class-access-modifier "package" \
    --java-nonnull-annotation "androidx.annotation.NonNull" \
    --ident-java-field mFooBar \
    \
    --kotlin-out "$kotlin_out" \
    --kotlin-package "$kotlin_package" \
    --kotlin-support-package "$kotlin_support_package" \
    --kotlin-cinterop-package "$kotlin_cinterop_package" \
    \
    --cpp-out "$cpp_out" \
    --cpp-namespace crux::generated \
    --ident-cpp-enum-type foo_bar \
    \
    --jni-out "$jni_out" \
    --ident-jni-class NativeFooBar \
    --ident-jni-file NativeFooBar \
    \
    --objc-out "$objc_out" \
    --objcpp-out "$objc_out" \
    --objc-type-prefix CRX \
    \
    --idl "$in"

echo "djinni completed."
