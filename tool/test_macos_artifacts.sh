#!/usr/bin/env bash
# Link the ABI boundary harness against the macOS libraries.
# The library in build/native_artifacts/<target>/ is a local build of
# tool/build_native_artifact.sh, or else the released file
# (tool/prebuilt_artifacts.dart downloads it).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/artifact-runtime/macos"
mkdir -p "$build"

for target in macos-arm64 macos-x64; do
  [[ "$target" == macos-arm64 ]] && arch=arm64 || arch=x86_64
  library="$root/build/native_artifacts/$target/libimage_ffmpeg.dylib"
  [[ -f "$library" ]] || (cd "$root" && dart run tool/prebuilt_artifacts.dart "$target")
  binary="$build/abi_boundary_$arch"
  xcrun --sdk macosx clang -std=c11 -O2 -Wall -Wextra -Werror \
    -arch "$arch" -mmacosx-version-min=12.0 \
    -I"$root/src" "$root/tool/support/abi_boundary_test.c" \
    "$library" -Wl,-rpath,"$(dirname "$library")" -o "$binary"
  if [[ "$arch" == x86_64 && "$(uname -m)" != x86_64 ]]; then
    arch -x86_64 "$binary"
  else
    "$binary"
  fi
  echo "PASS: $target library"
done
