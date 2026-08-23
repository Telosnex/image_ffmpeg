#!/usr/bin/env bash
# Instrument the package-owned C boundary and run its 6,144 malformed calls.
# FFmpeg/libaom/zlib are the exact profile-9 static inputs used by the artifact.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || {
  echo 'This sanitizer profile currently requires Apple clang on macOS.' >&2
  exit 1
}
"$root/tool/fetch_native_sources.sh"

profile="$root/build/native/macos-arm64-v9"
ffmpeg="$profile/ffmpeg/install"
aom="$profile/aom/install"
zlib="$profile/zlib/install"
for archive in \
  "$ffmpeg/lib/libavformat.a" "$ffmpeg/lib/libavcodec.a" \
  "$ffmpeg/lib/libswscale.a" "$ffmpeg/lib/libavutil.a" \
  "$aom/lib/libaom.a" "$zlib/lib/libz.a"; do
  [[ -f "$archive" ]] || {
    echo "Missing profile-9 static input: $archive" >&2
    echo 'Build macos-arm64 first.' >&2
    exit 1
  }
done

build="$root/build/macos-arm64-sanitized"
rm -rf "$build"
mkdir -p "$build"
sanitizers='-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all'
xcrun --sdk macosx clang -std=c11 -O1 -g -Wall -Wextra -Werror \
  $sanitizers -mmacosx-version-min=12.0 \
  -DIMAGE_FFMPEG_WITH_FFMPEG=1 \
  -I"$root/src" -I"$ffmpeg/include" \
  "$root/src/image_ffmpeg.c" "$root/tool/support/abi_boundary_test.c" \
  "$ffmpeg/lib/libavformat.a" "$ffmpeg/lib/libavcodec.a" \
  "$ffmpeg/lib/libswscale.a" "$ffmpeg/lib/libavutil.a" \
  "$aom/lib/libaom.a" "$zlib/lib/libz.a" -lm \
  -o "$build/abi_boundary_test"
# Apple clang does not implement LeakSanitizer. Heap bounds, UAF, double-free,
# and all UndefinedBehaviorSanitizer checks remain enabled.
ASAN_OPTIONS='abort_on_error=1:detect_leaks=0:strict_string_checks=1' \
UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1' \
  "$build/abi_boundary_test"
echo 'PASS: image_ffmpeg C boundary under ASan + UBSan'
