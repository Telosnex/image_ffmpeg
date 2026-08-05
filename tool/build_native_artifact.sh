#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"

ffmpeg_commit=d32b387f2b0a484599d4587d651891f0c63c4238
aom_commit=10aece4157eb79315da205f39e19bf6ab3ee30d0
zlib_commit=51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf
profile_version=8

usage() {
  cat >&2 <<'EOF'
Usage: tool/build_native_artifact.sh <target>

Targets:
  macos-arm64              macos-x64
  ios-arm64-iphoneos       ios-arm64-iphonesimulator
  ios-x64-iphonesimulator
  android-arm              android-arm64              android-x64
  linux-arm64              linux-x64
  windows-x64

Apple targets require Xcode, Android targets require ANDROID_NDK_HOME (or a
standard Android SDK installation), and Linux/Windows targets use Linux
compilers directly or the provided Docker wrappers.
EOF
  exit 64
}

ffmpeg_source="$root/third_party/ffmpeg"
aom_source="$root/third_party/aom"
zlib_source="$root/third_party/zlib"

require_commit() {
  local directory="$1" expected="$2" name="$3"
  if [[ ! -d "$directory/.git" ]]; then
    echo "$name source is missing; run tool/fetch_native_sources.sh" >&2
    exit 1
  fi
  local actual
  actual="$(git -C "$directory" rev-parse HEAD)"
  if [[ "$actual" != "$expected" ]]; then
    echo "$name source is not pinned: expected $expected, found $actual" >&2
    exit 1
  fi
}

require_commit "$ffmpeg_source" "$ffmpeg_commit" FFmpeg
require_commit "$aom_source" "$aom_commit" libaom
require_commit "$zlib_source" "$zlib_commit" zlib
command -v cmake >/dev/null || { echo 'cmake is required' >&2; exit 1; }

os=
ffmpeg_arch=
artifact_arch=
cc=
cxx=
ar=
ranlib=
strip_tool=
common_cflags='-O3 -fPIC'
common_ldflags=
output_name=
shared_flags=()
cmake_platform_args=()
configure_platform_args=()
verification_tool=
system_libraries=(-lm)

case "$target" in
  macos-arm64|macos-x64)
    os=macos
    [[ "$target" == macos-arm64 ]] && {
      ffmpeg_arch=arm64; artifact_arch=arm64;
    } || {
      ffmpeg_arch=x86_64; artifact_arch=x86_64;
    }
    sdk=macosx
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cc="$(xcrun --sdk "$sdk" -f clang)"
    cxx="$(xcrun --sdk "$sdk" -f clang++)"
    ar="$(xcrun --sdk "$sdk" -f ar)"
    ranlib="$(xcrun --sdk "$sdk" -f ranlib)"
    strip_tool="$(xcrun --sdk "$sdk" -f strip)"
    common_cflags+=" -arch $artifact_arch -mmacosx-version-min=12.0 -isysroot $sdk_path"
    common_ldflags="-arch $artifact_arch -mmacosx-version-min=12.0 -isysroot $sdk_path"
    cmake_platform_args=(
      -DCMAKE_OSX_ARCHITECTURES="$artifact_arch"
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
      -DCMAKE_OSX_SYSROOT="$sdk_path"
    )
    configure_platform_args=(--target-os=darwin --arch="$ffmpeg_arch")
    output_name=libimage_ffmpeg.dylib
    shared_flags=(
      -dynamiclib -Wl,-dead_strip -Wl,-headerpad_max_install_names
      -Wl,-install_name,@rpath/libimage_ffmpeg.dylib
    )
    verification_tool=otool
    ;;
  ios-arm64-iphoneos|ios-arm64-iphonesimulator|ios-x64-iphonesimulator)
    os=ios
    if [[ "$target" == ios-x64-iphonesimulator ]]; then
      ffmpeg_arch=x86_64; artifact_arch=x86_64
    else
      ffmpeg_arch=arm64; artifact_arch=arm64
    fi
    [[ "$target" == *-iphoneos ]] && sdk=iphoneos || sdk=iphonesimulator
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    cc="$(xcrun --sdk "$sdk" -f clang)"
    cxx="$(xcrun --sdk "$sdk" -f clang++)"
    ar="$(xcrun --sdk "$sdk" -f ar)"
    ranlib="$(xcrun --sdk "$sdk" -f ranlib)"
    strip_tool="$(xcrun --sdk "$sdk" -f strip)"
    if [[ "$sdk" == iphoneos ]]; then
      minimum_flag=-miphoneos-version-min=13.0
    else
      minimum_flag=-mios-simulator-version-min=13.0
    fi
    common_cflags+=" -arch $artifact_arch $minimum_flag -isysroot $sdk_path"
    common_ldflags="-arch $artifact_arch $minimum_flag -isysroot $sdk_path"
    cmake_platform_args=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_ARCHITECTURES="$artifact_arch"
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
      -DCMAKE_OSX_SYSROOT="$sdk_path"
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    )
    configure_platform_args=(--target-os=darwin --arch="$ffmpeg_arch" --enable-cross-compile)
    output_name=libimage_ffmpeg.dylib
    shared_flags=(
      -dynamiclib -Wl,-dead_strip -Wl,-headerpad_max_install_names
      -Wl,-install_name,@rpath/libimage_ffmpeg.dylib
    )
    verification_tool=otool
    ;;
  android-arm|android-arm64|android-x64)
    os=android
    android_api="${IMAGE_FFMPEG_ANDROID_API:-24}"
    ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    if [[ -z "$ndk" ]]; then
      ndk="$HOME/Library/Android/sdk/ndk/28.2.13676358"
    fi
    [[ -d "$ndk" ]] || { echo 'Set ANDROID_NDK_HOME to an Android NDK.' >&2; exit 1; }
    case "$(uname -s)" in
      Darwin) ndk_host=darwin-x86_64 ;;
      Linux) ndk_host=linux-x86_64 ;;
      *) echo 'Android artifacts can only be built on macOS or Linux.' >&2; exit 1 ;;
    esac
    llvm_bin="$ndk/toolchains/llvm/prebuilt/$ndk_host/bin"
    case "$target" in
      android-arm)
        ffmpeg_arch=arm; artifact_arch=arm; android_abi=armeabi-v7a
        compiler_prefix=armv7a-linux-androideabi
        configure_platform_args=(--target-os=android --arch=arm --cpu=armv7-a --enable-cross-compile)
        ;;
      android-arm64)
        ffmpeg_arch=aarch64; artifact_arch=aarch64; android_abi=arm64-v8a
        compiler_prefix=aarch64-linux-android
        configure_platform_args=(--target-os=android --arch=aarch64 --enable-cross-compile)
        ;;
      android-x64)
        ffmpeg_arch=x86_64; artifact_arch=x86_64; android_abi=x86_64
        compiler_prefix=x86_64-linux-android
        configure_platform_args=(--target-os=android --arch=x86_64 --enable-cross-compile)
        ;;
    esac
    cc="$llvm_bin/${compiler_prefix}${android_api}-clang"
    cxx="$llvm_bin/${compiler_prefix}${android_api}-clang++"
    ar="$llvm_bin/llvm-ar"
    ranlib="$llvm_bin/llvm-ranlib"
    strip_tool="$llvm_bin/llvm-strip"
    common_ldflags='-Wl,-z,max-page-size=16384'
    cmake_platform_args=(
      -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="$android_abi"
      -DANDROID_PLATFORM="android-$android_api"
      -DANDROID_STL=c++_static
    )
    output_name=libimage_ffmpeg.so
    shared_flags=(-shared -Wl,-soname,libimage_ffmpeg.so -Wl,-z,max-page-size=16384)
    verification_tool="$llvm_bin/llvm-readelf"
    ;;
  windows-x64)
    os=windows
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Windows artifacts must be cross-built on Linux (use tool/build_native_windows_docker.sh).' >&2
      exit 1
    }
    ffmpeg_arch=x86_64; artifact_arch=x86_64
    cc="${CC:-x86_64-w64-mingw32-gcc}"
    cxx="${CXX:-x86_64-w64-mingw32-g++}"
    ar="${AR:-x86_64-w64-mingw32-ar}"
    ranlib="${RANLIB:-x86_64-w64-mingw32-ranlib}"
    strip_tool="${STRIP:-x86_64-w64-mingw32-strip}"
    configure_platform_args=(
      --target-os=mingw32 --arch=x86_64 --enable-cross-compile
      --cross-prefix=x86_64-w64-mingw32-
    )
    cmake_platform_args=(
      -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_SYSTEM_PROCESSOR=x86_64
      -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx"
      -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
    )
    output_name=image_ffmpeg.dll
    shared_flags=(-shared -Wl,--enable-auto-image-base -Wl,--no-insert-timestamp)
    verification_tool="${OBJDUMP:-x86_64-w64-mingw32-objdump}"
    system_libraries=(-lm -lbcrypt)
    ;;
  linux-arm64|linux-x64)
    os=linux
    [[ "$(uname -s)" == Linux ]] || {
      echo 'Linux artifacts must be built on Linux (use tool/build_native_linux_docker.sh).' >&2
      exit 1
    }
    if [[ "$target" == linux-arm64 ]]; then
      ffmpeg_arch=aarch64; artifact_arch=aarch64
      cc="${CC:-aarch64-linux-gnu-gcc}"
      cxx="${CXX:-aarch64-linux-gnu-g++}"
      ar="${AR:-aarch64-linux-gnu-ar}"
      ranlib="${RANLIB:-aarch64-linux-gnu-ranlib}"
      strip_tool="${STRIP:-aarch64-linux-gnu-strip}"
      configure_platform_args=(--target-os=linux --arch=aarch64 --enable-cross-compile --cross-prefix=aarch64-linux-gnu-)
      cmake_platform_args=(
        -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64
        -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx"
      )
    else
      ffmpeg_arch=x86_64; artifact_arch=x86_64
      cc="${CC:-gcc}"; cxx="${CXX:-g++}"; ar="${AR:-ar}"
      ranlib="${RANLIB:-ranlib}"; strip_tool="${STRIP:-strip}"
      configure_platform_args=(--target-os=linux --arch=x86_64)
    fi
    output_name=libimage_ffmpeg.so
    shared_flags=(-shared -Wl,-soname,libimage_ffmpeg.so -Wl,-z,relro,-z,now)
    verification_tool="${READELF:-readelf}"
    ;;
  *) usage ;;
esac

if [[ "$(uname -s)" == Darwin ]]; then
  host_cc="$(xcrun --sdk macosx -f clang) -isysroot $(xcrun --sdk macosx --show-sdk-path)"
else
  host_cc="${HOST_CC:-cc}"
fi

for tool in "$cc" "$cxx" "$ar" "$ranlib" "$strip_tool"; do
  command -v "$tool" >/dev/null || { echo "Required tool not found: $tool" >&2; exit 1; }
done

build_root="$root/build/native/$target-v$profile_version"
zlib_build="$build_root/zlib"
zlib_prefix="$zlib_build/install"
aom_build="$build_root/aom"
aom_prefix="$aom_build/install"
ffmpeg_build="$build_root/ffmpeg"
ffmpeg_prefix="$ffmpeg_build/install"
artifact_directory="$root/native_artifacts/$target"
artifact="$artifact_directory/$output_name"
jobs="${IMAGE_FFMPEG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"

if [[ ! -f "$zlib_build/.image_ffmpeg_complete" ]]; then
  rm -rf "$zlib_build"
  cmake -S "$zlib_source" -B "$zlib_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$zlib_prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_COMPILER="$cc" \
    -DCMAKE_C_FLAGS="$common_cflags" \
    -DBUILD_SHARED_LIBS=OFF \
    -DZLIB_BUILD_EXAMPLES=OFF \
    "${cmake_platform_args[@]}"
  cmake --build "$zlib_build" --parallel "$jobs"
  cmake --install "$zlib_build"
  touch "$zlib_build/.image_ffmpeg_complete"
fi
zlib_archive="$(find "$zlib_prefix" -type f \( -name 'libz.a' -o -name 'libzlibstatic.a' \) -print -quit)"
[[ -f "$zlib_archive" ]] || { echo 'zlib static archive is missing' >&2; exit 1; }
if [[ "$(basename "$zlib_archive")" != libz.a ]]; then
  cp "$zlib_archive" "$zlib_prefix/lib/libz.a"
  zlib_archive="$zlib_prefix/lib/libz.a"
fi
# zlib's CMake project installs shared and static libraries together. Remove
# the shared copy so FFmpeg's `-lz` configure check and final link cannot
# accidentally select it.
find "$zlib_prefix" -type f \( -name 'libz*.dylib' -o -name 'libz.so*' -o -name 'libzlib.dll' \) -delete

if [[ ! -f "$aom_build/.image_ffmpeg_complete" ]]; then
  rm -rf "$aom_build"
  cmake -S "$aom_source" -B "$aom_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$aom_prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_COMPILER="$cc" \
    -DCMAKE_CXX_COMPILER="$cxx" \
    -DCMAKE_C_FLAGS="$common_cflags" \
    -DCMAKE_CXX_FLAGS="$common_cflags" \
    -DBUILD_SHARED_LIBS=OFF \
    -DAOM_TARGET_CPU=generic \
    -DENABLE_DOCS=OFF \
    -DENABLE_EXAMPLES=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_TOOLS=OFF \
    -DENABLE_NASM=OFF \
    -DCONFIG_AV1_DECODER=1 \
    -DCONFIG_AV1_ENCODER=0 \
    -DCONFIG_MULTITHREAD=0 \
    -DCONFIG_RUNTIME_CPU_DETECT=0 \
    -DCONFIG_WEBM_IO=0 \
    "${cmake_platform_args[@]}"
  cmake --build "$aom_build" --target aom --parallel "$jobs"
  mkdir -p "$aom_prefix/include/aom" "$aom_prefix/lib"
  cp "$aom_build/libaom.a" "$aom_prefix/lib/libaom.a"
  for header in aom.h aom_codec.h aom_decoder.h aom_frame_buffer.h aom_image.h aom_integer.h aomdx.h; do
    cp "$aom_source/aom/$header" "$aom_prefix/include/aom/$header"
  done
  touch "$aom_build/.image_ffmpeg_complete"
fi

if [[ ! -f "$ffmpeg_build/.image_ffmpeg_complete" ]]; then
  rm -rf "$ffmpeg_build"
  mkdir -p "$ffmpeg_build"
  export AOM_PREFIX="$aom_prefix"
  (
    cd "$ffmpeg_build"
    "$ffmpeg_source/configure" \
      --prefix="$ffmpeg_prefix" \
      "${configure_platform_args[@]}" \
      --cc="$cc" --cxx="$cxx" --ar="$ar" --ranlib="$ranlib" \
      --host-cc="$host_cc" \
      --pkg-config="$root/tool/pkg_config_aom.sh" \
      --pkg-config-flags=--static \
      --enable-static --disable-shared --enable-pic --disable-asm \
      --disable-stripping --disable-programs --disable-doc --disable-debug \
      --disable-runtime-cpudetect --disable-autodetect --disable-network \
      --disable-iconv --disable-bzlib --disable-lzma --enable-zlib \
      --disable-avdevice --disable-avfilter --enable-avformat \
      --disable-swresample --disable-everything \
      --enable-libaom \
      --enable-decoder=mjpeg,png,apng,webp,webp_anim,gif,bmp,tiff,psd,libaom_av1 \
      --enable-encoder=mjpeg,png \
      --enable-demuxer=image_jpeg_pipe,image_png_pipe,apng,image_webp_pipe,webp_anim,image_gif_pipe,image_bmp_pipe,image_tiff_pipe,image_psd_pipe,ico,mov \
      --enable-small \
      --extra-cflags="$common_cflags -I$zlib_prefix/include" \
      --extra-ldflags="$common_ldflags -L$(dirname "$zlib_archive")"
    make -j"$jobs" libavformat/libavformat.a libavcodec/libavcodec.a \
      libavutil/libavutil.a libswscale/libswscale.a
    make install-libs install-headers
  )
  touch "$ffmpeg_build/.image_ffmpeg_complete"
fi

mkdir -p "$artifact_directory"
exports="$build_root/exports.txt"
if [[ "$os" == macos || "$os" == ios ]]; then prefix=_; else prefix=; fi
cat > "$exports" <<EOF
${prefix}image_ffmpeg_abi_version
${prefix}image_ffmpeg_build_info
${prefix}image_ffmpeg_has_ffmpeg
${prefix}image_ffmpeg_probe_image
${prefix}image_ffmpeg_decode_image_rgba
${prefix}image_ffmpeg_decode_jpeg_rgba
${prefix}image_ffmpeg_encode_jpeg_rgba
${prefix}image_ffmpeg_encode_jpeg_rgba_ex
${prefix}image_ffmpeg_encode_png_rgba
${prefix}image_ffmpeg_transcode_image
${prefix}image_ffmpeg_image_release
${prefix}image_ffmpeg_buffer_release
${prefix}image_ffmpeg_encoded_image_release
${prefix}image_ffmpeg_error_message
EOF

export_flags=()
if [[ "$os" == macos || "$os" == ios ]]; then
  export_flags=(-Wl,-exported_symbols_list,"$exports")
elif [[ "$os" == windows ]]; then
  definition_file="$build_root/image_ffmpeg.def"
  {
    echo 'LIBRARY image_ffmpeg'
    echo 'EXPORTS'
    sed 's/^/  /' "$exports"
  } > "$definition_file"
  export_flags=("$definition_file")
else
  version_script="$build_root/exports.map"
  {
    echo 'IMAGE_FFMPEG_2 {'
    echo '  global:'
    sed 's/^/    /; s/$/;/' "$exports"
    echo '  local: *;'
    echo '};'
  } > "$version_script"
  export_flags=(-Wl,--version-script="$version_script" -Wl,--exclude-libs,ALL)
fi

"$cc" "${shared_flags[@]}" "$root/src/image_ffmpeg.c" \
  -I"$root/src" -I"$ffmpeg_prefix/include" \
  -DIMAGE_FFMPEG_WITH_FFMPEG=1 $common_cflags $common_ldflags \
  "$ffmpeg_prefix/lib/libavformat.a" \
  "$ffmpeg_prefix/lib/libavcodec.a" \
  "$ffmpeg_prefix/lib/libswscale.a" \
  "$ffmpeg_prefix/lib/libavutil.a" \
  "$aom_prefix/lib/libaom.a" "$zlib_archive" \
  "${system_libraries[@]}" "${export_flags[@]}" -o "$artifact"
"$strip_tool" -x "$artifact" 2>/dev/null || "$strip_tool" --strip-unneeded "$artifact"

case "$os" in
  macos|ios)
    actual_arch="$(lipo -archs "$artifact")"
    [[ "$actual_arch" == "$artifact_arch" ]] || {
      echo "Wrong artifact architecture: expected $artifact_arch, got $actual_arch" >&2; exit 1;
    }
    if otool -L "$artifact" | grep -E '/opt/homebrew|/usr/local|libav(codec|format|util)|libswscale|libaom|libz'; then
      echo 'Artifact unexpectedly has a non-system codec dependency.' >&2; exit 1;
    fi
    ;;
  android|linux)
    if "$verification_tool" -d "$artifact" | grep -E 'libav(codec|format|util)|libswscale|libaom|libz'; then
      echo 'Artifact unexpectedly has a codec dependency.' >&2; exit 1;
    fi
    ;;
  windows)
    if "$verification_tool" -p "$artifact" | grep -Ei 'DLL Name:.*(avcodec|avformat|avutil|swscale|aom|zlib)'; then
      echo 'Artifact unexpectedly has a codec dependency.' >&2; exit 1;
    fi
    ;;
esac

actual_exports="$build_root/actual_exports.txt"
case "$os" in
  macos|ios)
    nm -gU "$artifact" | awk '{print $3}' | grep '^_image_ffmpeg_' \
      | sort > "$actual_exports"
    ;;
  android)
    "$llvm_bin/llvm-nm" -D --defined-only "$artifact" | awk '{print $3}' \
      | sed 's/@@.*//' | grep '^image_ffmpeg_' | sort > "$actual_exports"
    ;;
  linux)
    "${NM:-nm}" -D --defined-only "$artifact" | awk '{print $3}' \
      | sed 's/@@.*//' | grep '^image_ffmpeg_' | sort > "$actual_exports"
    ;;
  windows)
    "$verification_tool" -p "$artifact" \
      | awk '/\[[[:space:]]*[0-9]+\] image_ffmpeg_/ {print $NF}' \
      | sort > "$actual_exports"
    ;;
esac
sort "$exports" > "$build_root/expected_exports.txt"
if ! diff -u "$build_root/expected_exports.txt" "$actual_exports"; then
  echo 'Artifact export surface does not match the shim ABI.' >&2
  exit 1
fi

if command -v shasum >/dev/null; then
  sha256="$(shasum -a 256 "$artifact" | awk '{print $1}')"
else
  sha256="$(sha256sum "$artifact" | awk '{print $1}')"
fi
size="$(wc -c < "$artifact" | tr -d ' ')"
echo "Built $artifact"
echo "target=$target"
echo "sha256=$sha256"
echo "size=$size"
