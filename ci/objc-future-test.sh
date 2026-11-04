#!/usr/bin/env bash
# Builds and runs ci/objc/future_test.mm. The test checks that djinni::FutureAdaptor::fromCpp rejects the DJFuture
# for every exception of a failed C++ future. Each case runs in its own process, so a crash fails only that case.
# macOS only. There is no Bazel step.
#
# Environment:
#   CXX  the C++ compiler (default: clang++)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/djinni-objc-future.XXXXXX")"
trap 'rm -rf "$work"' EXIT

"${CXX:-clang++}" -std=c++17 -ObjC++ -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
  -I "$repo_root/support-lib/objc" -I "$repo_root/support-lib/cpp" \
  "$repo_root/ci/objc/future_test.mm" "$repo_root/support-lib/objc/DJFuture.mm" \
  -framework Foundation -o "$work/future-test"

status=0
for name in std-exception non-std-exception void-std-exception void-non-std-exception void-value; do
  if "$work/future-test" "$name"; then
    echo "ok: $name"
  else
    echo "not ok: $name (exit $?)"
    status=1
  fi
done
exit "$status"
