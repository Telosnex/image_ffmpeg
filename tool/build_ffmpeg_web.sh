#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_directory="$root/third_party/ffmpeg"
build_directory="$root/build/ffmpeg-wasm"
install_directory="$build_directory/install"
aom_prefix="$root/build/aom-wasm/install"

command -v emcc >/dev/null || {
  echo "emcc not found; activate the Emscripten SDK first" >&2
  exit 1
}
if [[ ! -x "$source_directory/configure" ]]; then
  echo "FFmpeg source missing; run tool/fetch_ffmpeg.sh first" >&2
  exit 1
fi
if [[ ! -f "$aom_prefix/lib/libaom.a" ]]; then
  echo "Reduced libaom missing; run tool/build_aom_web.sh first" >&2
  exit 1
fi
export AOM_PREFIX="$aom_prefix"

configuration_version=10
if [[ ! -f "$build_directory/.image_ffmpeg_config_version" ]] ||
    [[ "$(cat "$build_directory/.image_ffmpeg_config_version")" != "$configuration_version" ]]; then
  rm -rf "$build_directory"
fi
mkdir -p "$build_directory"
cd "$build_directory"

if [[ ! -f ffbuild/config.mak ]]; then
  emconfigure "$source_directory/configure" \
    --prefix="$install_directory" \
    --target-os=none \
    --arch=x86_32 \
    --enable-cross-compile \
    --cc=emcc \
    --cxx=em++ \
    --objcc=emcc \
    --dep-cc=emcc \
    --ar=emar \
    --ranlib=emranlib \
    --nm=emnm \
    --pkg-config="$root/tool/pkg_config_aom.sh" \
    --pkg-config-flags=--static \
    --enable-static \
    --disable-shared \
    --disable-asm \
    --disable-stripping \
    --disable-programs \
    --disable-doc \
    --disable-debug \
    --disable-runtime-cpudetect \
    --disable-autodetect \
    --disable-pthreads \
    --disable-w32threads \
    --disable-os2threads \
    --disable-network \
    --disable-iconv \
    --disable-bzlib \
    --disable-lzma \
    --enable-zlib \
    --disable-avdevice \
    --disable-avfilter \
    --enable-avformat \
    --disable-swresample \
    --disable-everything \
    --enable-libaom \
    --enable-decoder=mjpeg,png,apng,webp,webp_anim,gif,bmp,tiff,psd,libaom_av1 \
    --enable-encoder=mjpeg,png \
    --enable-demuxer=image_jpeg_pipe,image_png_pipe,apng,image_webp_pipe,webp_anim,image_gif_pipe,image_bmp_pipe,image_tiff_pipe,image_psd_pipe,ico,mov \
    --enable-small \
    --extra-cflags='-O3 -sUSE_ZLIB=1' \
    --extra-ldflags=-sUSE_ZLIB=1
  printf '%s' "$configuration_version" > .image_ffmpeg_config_version
fi

jobs="${IMAGE_FFMPEG_BUILD_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
emmake make -j"$jobs" \
  libavformat/libavformat.a \
  libavcodec/libavcodec.a \
  libavutil/libavutil.a \
  libswscale/libswscale.a
emmake make install-libs install-headers

echo "Installed reduced FFmpeg Wasm libraries to $install_directory"
