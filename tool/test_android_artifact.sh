#!/usr/bin/env bash
# Execute the ABI boundary corpus against the exact Android artifact on a
# connected device/emulator. Set IMAGE_FFMPEG_ANDROID_AVD to start an AVD.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"
ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$sdk/ndk/28.2.13676358}}"
[[ -x "$adb" && -d "$ndk" ]] || { echo 'Android SDK/NDK is missing.' >&2; exit 1; }

started=false; emulator_pid=
cleanup() {
  "$adb" shell 'rm -rf /data/local/tmp/image_ffmpeg_boundary' >/dev/null 2>&1 || true
  if [[ "$started" == true && "${IMAGE_FFMPEG_KEEP_ANDROID_RUNNING:-0}" != 1 ]]; then
    "$adb" emu kill >/dev/null 2>&1 || true
    [[ -z "$emulator_pid" ]] || kill "$emulator_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if ! "$adb" get-state >/dev/null 2>&1; then
  avd="${IMAGE_FFMPEG_ANDROID_AVD:-}"
  [[ -n "$avd" ]] || { echo 'No device; set IMAGE_FFMPEG_ANDROID_AVD.' >&2; exit 1; }
  "$emulator" -avd "$avd" -no-window -no-audio -no-boot-anim \
    -gpu swiftshader_indirect >"$root/build/android-emulator.log" 2>&1 &
  emulator_pid=$!; started=true; "$adb" wait-for-device
fi
for _ in $(seq 1 180); do
  [[ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 1
done
[[ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] || {
  echo 'Android did not finish booting.' >&2; exit 1;
}

abi="$("$adb" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$abi" in
  arm64-v8a) target=android-arm64; compiler=aarch64-linux-android24-clang ;;
  armeabi-v7a) target=android-arm; compiler=armv7a-linux-androideabi24-clang ;;
  x86_64) target=android-x64; compiler=x86_64-linux-android24-clang ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 1 ;;
esac
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) exit 1 ;; esac
cc="$ndk/toolchains/llvm/prebuilt/$host/bin/$compiler"
artifact="$root/native_artifacts/$target/libimage_ffmpeg.so"
build="$root/build/android-device-boundary"
rm -rf "$build" && mkdir -p "$build"
"$cc" -std=c11 -O2 -Wall -Wextra -Werror -I"$root/src" \
  "$root/tool/support/abi_boundary_test.c" -L"$(dirname "$artifact")" \
  -limage_ffmpeg -Wl,-rpath,'$ORIGIN' -o "$build/abi_boundary_test"
remote=/data/local/tmp/image_ffmpeg_boundary
"$adb" shell "rm -rf $remote && mkdir $remote"
"$adb" push "$build/abi_boundary_test" "$artifact" "$remote/" >/dev/null
"$adb" shell "chmod 755 $remote/abi_boundary_test && cd $remote && LD_LIBRARY_PATH=. ./abi_boundary_test --quick"
echo "PASS: exact $target artifact on Android API $("$adb" shell getprop ro.build.version.sdk | tr -d '\r')"
