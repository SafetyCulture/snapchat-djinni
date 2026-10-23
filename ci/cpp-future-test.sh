#!/usr/bin/env bash
# Builds and runs ci/cpp/future_test.cpp, which checks djinni::Future and djinni::Promise on their own:
# a dropped promise, a moved promise, a replaced handler, and handlers that throw exceptions that do not derive from
# std::exception. It runs in C++17 and in C++20. The C++20 build does not compile the coroutine support of Future.hpp:
# Future.hpp turns it on with __cpp_coroutines, and clang does not define that macro (it defines __cpp_impl_coroutine).
# Any C++ compiler works; there is no Bazel step.
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
