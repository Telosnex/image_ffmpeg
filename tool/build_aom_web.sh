#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_directory="$root/third_party/aom"
build_directory="$root/build/aom-wasm"
install_directory="$build_directory/install"

command -v emcc >/dev/null || {
  echo "emcc not found; activate the Emscripten SDK first" >&2
  exit 1
}
command -v cmake >/dev/null || {
  echo "cmake not found" >&2
  exit 1
}
if [[ ! -f "$source_directory/CMakeLists.txt" ]]; then
  echo "libaom source missing; run tool/fetch_aom.sh first" >&2
  exit 1
fi
if [[ -z "${EMSDK:-}" ]]; then
  echo "EMSDK is not set; activate the Emscripten SDK first" >&2
  exit 1
fi

toolchain="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
if [[ ! -f "$toolchain" ]]; then
  echo "Emscripten CMake toolchain not found at $toolchain" >&2
  exit 1
fi

configuration_version=1
if [[ ! -f "$build_directory/.image_ffmpeg_config_version" ]] ||
    [[ "$(cat "$build_directory/.image_ffmpeg_config_version")" != "$configuration_version" ]]; then
  rm -rf "$build_directory"
fi
mkdir -p "$build_directory"

if [[ ! -f "$build_directory/CMakeCache.txt" ]]; then
  cmake -S "$source_directory" -B "$build_directory" \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_directory" \
    -DBUILD_SHARED_LIBS=OFF \
    -DAOM_TARGET_CPU=generic \
    -DENABLE_DOCS=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_TOOLS=OFF \
    -DCONFIG_AV1_DECODER=1 \
    -DCONFIG_AV1_ENCODER=0 \
    -DCONFIG_MULTITHREAD=0 \
    -DCONFIG_RUNTIME_CPU_DETECT=0 \
    -DCONFIG_WEBM_IO=0 \
    -DAOM_EXTRA_C_FLAGS=-O3 \
    -DAOM_EXTRA_CXX_FLAGS=-O3
  printf '%s' "$configuration_version" > \
    "$build_directory/.image_ffmpeg_config_version"
fi

jobs="${IMAGE_FFMPEG_BUILD_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
cmake --build "$build_directory" --target aom --parallel "$jobs"

# libaom's decoder-only Emscripten configuration does not generate aom.pc,
# which makes its generic CMake install target fail. Install the small public
# decoder surface and archive explicitly instead.
mkdir -p "$install_directory/include/aom" "$install_directory/lib"
cp "$build_directory/libaom.a" "$install_directory/lib/libaom.a"
for header in \
  aom.h \
  aom_codec.h \
  aom_decoder.h \
  aom_frame_buffer.h \
  aom_image.h \
  aom_integer.h \
  aomdx.h; do
  cp "$source_directory/aom/$header" "$install_directory/include/aom/$header"
done

echo "Installed reduced libaom Wasm library to $install_directory"
