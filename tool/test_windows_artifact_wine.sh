#!/usr/bin/env bash
# Runtime-test the Windows x64 DLL under Wine.
# The library in build/native_artifacts/<target>/ is a local build of
# tool/build_native_artifact.sh, or else the released file
# (tool/prebuilt_artifacts.dart downloads it).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }
[[ -f "$root/build/native_artifacts/windows-x64/image_ffmpeg.dll" ]] ||
  (cd "$root" && dart run tool/prebuilt_artifacts.dart windows-x64)

docker run --rm --platform linux/amd64 \
  -v "$root:/workspace" -w /workspace \
  debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
      gcc-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64 wine64 >/dev/null
    build=build/windows-x64-runtime-boundary
    rm -rf "$build" && mkdir -p "$build"
    x86_64-w64-mingw32-dlltool -d src/exports_windows.def \
      -D image_ffmpeg.dll -l "$build/libimage_ffmpeg.dll.a"
    x86_64-w64-mingw32-gcc-posix -std=c11 -O2 -Wall -Wextra -Werror \
      -static -static-libgcc -I src tool/support/abi_boundary_test.c \
      "$build/libimage_ffmpeg.dll.a" -o "$build/abi_boundary_test.exe"
    cp build/native_artifacts/windows-x64/image_ffmpeg.dll "$build/"
    cd "$build"
    export WINEDEBUG=-all WINEPREFIX=/tmp/image-ffmpeg-wine
    /usr/lib/wine/wine64 ./abi_boundary_test.exe --quick
  '
echo 'PASS: windows-x64 library under Wine'
