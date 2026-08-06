#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ffmpeg_prefix="$root/build/ffmpeg-wasm/install"
aom_prefix="$root/build/aom-wasm/install"
command -v emcc >/dev/null || {
  echo "emcc not found; install/activate the Emscripten SDK" >&2
  exit 1
}

ffmpeg_args=()
if [[ -f "$ffmpeg_prefix/lib/libavformat.a" ]] &&
    [[ -f "$aom_prefix/lib/libaom.a" ]]; then
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
else
  echo "Reduced FFmpeg/libaom Wasm libraries not found; building ABI scaffold only." >&2
  echo "Run tool/build_aom_web.sh and tool/build_ffmpeg_web.sh to enable decoding." >&2
fi

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
  -sEXPORTED_FUNCTIONS='["_malloc","_free","_image_ffmpeg_abi_version","_image_ffmpeg_build_info","_image_ffmpeg_has_ffmpeg","_image_ffmpeg_probe_image","_image_ffmpeg_decode_image_rgba","_image_ffmpeg_decode_image_rgba_box_average","_image_ffmpeg_decode_jpeg_rgba","_image_ffmpeg_encode_jpeg_rgba","_image_ffmpeg_encode_jpeg_rgba_ex","_image_ffmpeg_encode_png_rgba","_image_ffmpeg_transcode_image","_image_ffmpeg_image_release","_image_ffmpeg_buffer_release","_image_ffmpeg_encoded_image_release","_image_ffmpeg_error_message"]' \
  -sEXPORTED_RUNTIME_METHODS='["UTF8ToString","HEAPU8"]' \
  -o "$root/lib/web/image_ffmpeg_module.mjs"

echo "Built lib/web/image_ffmpeg_module.mjs and lib/web/image_ffmpeg_module.wasm"
