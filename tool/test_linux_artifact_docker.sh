#!/usr/bin/env bash
# Runtime-test the exact committed Linux artifact in a clean matching-arch
# glibc 2.31 container.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  linux-x64)
    platform=linux/amd64
    image='debian@sha256:de70627667ac77b32ab6858f1acddfb04a4ff3acc1095ac17dbc19fe5725bcb6'
    ;;
  linux-arm64)
    platform=linux/arm64
    image='debian@sha256:256e2eb1c47e91d91d1332b436b2efac5cd2511dc82fb78850fd01770cce2162'
    ;;
  *) echo "Usage: $0 <linux-x64|linux-arm64>" >&2; exit 64 ;;
esac
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

docker run --rm --platform "$platform" \
  -v "$root:/workspace" -w /workspace "$image" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends gcc libc6-dev >/dev/null
    target='"$target"'
    build="build/${target}-runtime-boundary"
    rm -rf "$build" && mkdir -p "$build"
    gcc -std=c11 -O2 -Wall -Wextra -Werror -I src \
      tool/support/abi_boundary_test.c \
      -L "native_artifacts/$target" -limage_ffmpeg \
      -pthread -Wl,-rpath,'"'"'$ORIGIN'"'"' -o "$build/abi_boundary_test"
    cp "native_artifacts/$target/libimage_ffmpeg.so" "$build/"
    "$build/abi_boundary_test"
  '
echo "PASS: exact $target artifact in clean $platform container"
