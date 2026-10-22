#!/usr/bin/env bash
# Runs the Kotlin JNI checks in the Docker image of the pipeline (Linux, JDK 17, g++).
#
# The image has no Kotlin compiler. The script downloads a pinned kotlinc and a pinned
# kotlinx-coroutines jar, checks their SHA-256 sums, and runs ci/kotlin-jni-check.sh (without the
# Crux IDL, which is in another repository) and ci/kotlin-jni-runtime-test.sh. A missing tool is an error.
#
# Environment:
#   KOTLIN_CI_CACHE    directory for the downloads (default: $TMPDIR/djinni-kotlin-ci)
#   HEAD_JAR           prebuilt //src:djinni_deploy.jar, skips the Bazel build
#   BAZEL_EXECUTABLE   the Bazel binary, as in src/build.sh (default: bazel)
set -euo pipefail

kotlin_version=2.4.21
kotlin_sha256=7cc140e76daf416a0424a5557f99afd7ca89ebd463ea1101261e3e01c33e75cd
coroutines_version=1.10.2
coroutines_sha256=5ca175b38df331fd64155b35cd8cae1251fa9ee369709b36d42e0a288ccce3fd

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cache="${KOTLIN_CI_CACHE:-${TMPDIR:-/tmp}/djinni-kotlin-ci}"
mkdir -p "$cache"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fetch() { # <url> <file> <sha256>
  if [ ! -f "$2" ] || [ "$(sha256 "$2")" != "$3" ]; then
    curl -fsSL --retry 3 -o "$2" "$1"
  fi
  if [ "$(sha256 "$2")" != "$3" ]; then
    echo "SHA-256 of $2 differs from $3" >&2
    exit 1
  fi
}

kotlin_zip="$cache/kotlin-compiler-$kotlin_version.zip"
fetch "https://github.com/JetBrains/kotlin/releases/download/v$kotlin_version/kotlin-compiler-$kotlin_version.zip" "$kotlin_zip" "$kotlin_sha256"
if [ ! -x "$cache/kotlinc-$kotlin_version/bin/kotlinc" ]; then
  rm -rf "$cache/unpack" "$cache/kotlinc-$kotlin_version"
  mkdir -p "$cache/unpack"
  unzip -q "$kotlin_zip" -d "$cache/unpack"
  mv "$cache/unpack/kotlinc" "$cache/kotlinc-$kotlin_version"
fi
coroutines_jar="$cache/kotlinx-coroutines-core-jvm-$coroutines_version.jar"
# repo1.maven.org fails behind a TLS-inspecting proxy. The SHA-256 pin makes the Google mirror safe.
fetch "https://maven-central.storage-download.googleapis.com/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/$coroutines_version/kotlinx-coroutines-core-jvm-$coroutines_version.jar" \
  "$coroutines_jar" "$coroutines_sha256"

if [ -z "${HEAD_JAR:-}" ]; then
  (cd "$repo_root" && "${BAZEL_EXECUTABLE:-bazel}" build //src:djinni_deploy.jar --host_conlyopt=-std=c90 >&2)
  HEAD_JAR="$repo_root/bazel-bin/src/djinni_deploy.jar"
fi

export HEAD_JAR
export PATH="$cache/kotlinc-$kotlin_version/bin:$PATH"
export KOTLINX_COROUTINES_JAR="$coroutines_jar"
export CI=1
export KOTLIN_JNI_CHECK_CRUX=0
# g++ with libstdc++ does not include <stdexcept> in support-lib/jni/DataRef_jni.cpp.
export CXX="${CXX:-g++}"
export CXXFLAGS="-include stdexcept ${CXXFLAGS:-}"

"$repo_root/ci/kotlin-jni-check.sh"
"$repo_root/ci/kotlin-jni-runtime-test.sh"
