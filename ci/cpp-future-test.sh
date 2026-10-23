#!/usr/bin/env bash
# Builds and runs ci/cpp/future_test.cpp. The test checks djinni::Future and djinni::Promise on their own: a dropped
# promise, a moved promise, a replaced handler, and a handler that throws an exception outside std::exception.
# It runs in C++17 and in C++20. Clang does not define __cpp_coroutines, so the coroutine support of Future.hpp is off.
# Any C++ compiler works. There is no Bazel step.
#
# Environment:
#   CXX  the C++ compiler (default: c++)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-cpp-future.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# No -Werror: the pipeline image has its own g++, and a new warning of that compiler must not fail a behaviour test.
for std in c++17 c++20; do
  echo "== [$std]"
  "${CXX:-c++}" "-std=$std" -Wall -Wextra -Wno-unused-parameter -I "$repo_root/support-lib/cpp" "$repo_root/ci/cpp/future_test.cpp" -pthread -o "$work/future-test"
  "$work/future-test"
done
