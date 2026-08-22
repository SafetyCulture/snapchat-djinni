#!/usr/bin/env bash
# The two release-lane steps (see .buildkite/pipeline.yml).
#
# package: builds the self-contained generator (a shell stub over a deploy jar, so one
#          artifact runs on macOS and Linux with just a JVM) and packages it with
#          support-lib/ as dist/djinni-generator.tar.gz + .sha256 sidecar.
# publish: uploads dist/ keyed by the build's tag, write-if-absent.
set -euo pipefail

BUCKET="${PREBUILT_MIRROR_BUCKET:-sc-mobile-packages}"
REGION="${PREBUILT_MIRROR_REGION:-us-east-1}"

case "${1:-}" in
  package)
    bazel build //generator:generator
    bazel run //generator:generator -- --help >/dev/null
    rm -rf dist && mkdir -p dist/pack
    cp bazel-bin/generator/djinni dist/pack/djinni
    chmod +x dist/pack/djinni
    cp -R support-lib dist/pack/support-lib
    tar czf dist/djinni-generator.tar.gz -C dist/pack djinni support-lib
    sha256sum < dist/djinni-generator.tar.gz | cut -d' ' -f1 > dist/djinni-generator.tar.gz.sha256
    ;;
  publish)
    TAG="${BUILDKITE_TAG:-${RELEASE_TAG:-}}"
    [ -n "$TAG" ] || TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
    [ -n "$TAG" ] || { echo "no tag names this revision — the tag is the artifact key"; exit 1; }
    buildkite-agent artifact download "dist/*" . --step build-generator
    KEY="mitti/djinni-generator/v1/${TAG}.tar.gz"
    if aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" >/dev/null 2>&1; then
      echo "already published: s3://$BUCKET/$KEY"
      exit 0
    fi
    # Sidecar first: a reader that can see the tarball must be able to verify it.
    aws s3 cp dist/djinni-generator.tar.gz.sha256 "s3://$BUCKET/$KEY.sha256" --region "$REGION" --only-show-errors
    aws s3 cp dist/djinni-generator.tar.gz "s3://$BUCKET/$KEY" --region "$REGION" --only-show-errors
    echo "published: s3://$BUCKET/$KEY"
    ;;
  *) echo "usage: $0 package|publish" >&2; exit 2 ;;
esac
