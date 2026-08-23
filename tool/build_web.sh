#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ffmpeg_prefix="$root/build/ffmpeg-wasm/install"
aom_prefix="$root/build/aom-wasm/install"
if ! command -v emcc >/dev/null; then
  if [[ -f "$root/../emsdk/emsdk_env.sh" ]]; then
    export EMSDK_QUIET=1
    # shellcheck disable=SC1091
    source "$root/../emsdk/emsdk_env.sh" >/dev/null
  else
    echo "emcc not found; install/activate the pinned Emscripten SDK" >&2
    exit 1
  fi
fi
emcc_version="$(emcc --version | sed -n '1p')"
grep -F '5.0.0 (a7c5deabd7c88ba1c38ebe988112256775f944c6)' \
  <<<"$emcc_version" >/dev/null || {
  echo 'Emscripten toolchain does not match production profile 9.' >&2
  exit 1
}

for archive in \
  "$ffmpeg_prefix/lib/libavformat.a" \
  "$ffmpeg_prefix/lib/libavcodec.a" \
  "$ffmpeg_prefix/lib/libswscale.a" \
  "$ffmpeg_prefix/lib/libavutil.a" \
  "$aom_prefix/lib/libaom.a"; do
  [[ -f "$archive" ]] || {
    echo "Missing production Wasm dependency: $archive" >&2
    echo "Run tool/build_aom_web.sh and tool/build_ffmpeg_web.sh first." >&2
    exit 1
  }
done
ffmpeg_args=(
  -I"$ffmpeg_prefix/include"
  -DIMAGE_FFMPEG_WITH_FFMPEG=1
  "$ffmpeg_prefix/lib/libavformat.a"
  "$ffmpeg_prefix/lib/libavcodec.a"
  "$ffmpeg_prefix/lib/libswscale.a"
  "$ffmpeg_prefix/lib/libavutil.a"
  "$aom_prefix/lib/libaom.a"
  -lm
)

emcc "$root/src/image_ffmpeg.c" \
  -I"$root/src" \
  "${ffmpeg_args[@]}" \
  -O3 \
  --no-entry \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sENVIRONMENT=web,worker,node \
  -sALLOW_MEMORY_GROWTH=1 \
  -sFILESYSTEM=0 \
  -sUSE_ZLIB=1 \
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_image_ffmpeg_abi_version","_image_ffmpeg_build_info","_image_ffmpeg_has_ffmpeg","_image_ffmpeg_probe_image","_image_ffmpeg_decode_image_rgba","_image_ffmpeg_decode_image_rgba_box_average","_image_ffmpeg_encode_jpeg_rgba","_image_ffmpeg_encode_png_rgba","_image_ffmpeg_transcode_image","_image_ffmpeg_image_release","_image_ffmpeg_buffer_release","_image_ffmpeg_encoded_image_release","_image_ffmpeg_error_message"]' \
  -sEXPORTED_RUNTIME_METHODS='["UTF8ToString","HEAPU8"]' \
  -o "$root/lib/web/image_ffmpeg_module.mjs"

echo "Built lib/web/image_ffmpeg_module.mjs and lib/web/image_ffmpeg_module.wasm"
