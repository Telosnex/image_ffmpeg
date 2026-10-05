#!/usr/bin/env bash
# Builds a Linux library in the Debian 11 container of the release workflow
# (glibc 2.31). Keep the image in sync with .github/workflows/native_release.yml.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64|linux-arm64) ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac

command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform linux/amd64 \
  -v "$root:/workspace" \
  -w /workspace \
  debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a \
  bash -c "tool/install_build_toolchain.sh $target && tool/fetch_native_sources.sh && tool/build_native_artifact.sh $target"
