#!/usr/bin/env bash
# Execute the ABI boundary corpus against the exact iOS Simulator dylib.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Requires macOS/Xcode.' >&2; exit 1; }

case "$(uname -m)" in
  arm64) arch_name=arm64; target=ios-arm64-iphonesimulator; minimum=14.0 ;;
  x86_64) arch_name=x86_64; target=ios-x64-iphonesimulator; minimum=13.0 ;;
  *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac
artifact="$root/native_artifacts/$target/libimage_ffmpeg.dylib"
[[ -f "$artifact" ]] || { echo "Missing $artifact" >&2; exit 1; }

devices_json="$(xcrun simctl list devices available -j)"
read -r udid initial_state < <(python3 -c '
import json, re, sys
obj=json.load(sys.stdin); candidates=[]
for runtime, devices in obj["devices"].items():
  if "SimRuntime.iOS-" not in runtime: continue
  version=tuple(int(x) for x in re.findall(r"\d+", runtime.rsplit("iOS-",1)[-1]))
  for device in devices:
    if device.get("isAvailable", True):
      candidates.append((device.get("state")=="Booted",version,device))
if not candidates: raise SystemExit("No available iOS simulator")
candidates.sort(key=lambda x:(x[0],x[1]),reverse=True)
d=candidates[0][2]; print(d["udid"],d.get("state","Shutdown"))
' <<<"$devices_json")
booted_here=false
cleanup() {
  if [[ "$booted_here" == true && "${IMAGE_FFMPEG_KEEP_SIMULATOR_BOOTED:-0}" != 1 ]]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
if [[ "$initial_state" != Booted ]]; then xcrun simctl boot "$udid"; booted_here=true; fi
xcrun simctl bootstatus "$udid" -b

build="$root/build/ios-simulator-boundary"
rm -rf "$build" && mkdir -p "$build"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -std=c11 -O2 -Wall -Wextra -Werror \
  -arch "$arch_name" -mios-simulator-version-min="$minimum" -isysroot "$sdk" \
  -I"$root/src" "$root/tool/support/abi_boundary_test.c" "$artifact" \
  -Wl,-rpath,@executable_path -o "$build/abi_boundary_test"
cp "$artifact" "$build/libimage_ffmpeg.dylib"
codesign -s - --force "$build/abi_boundary_test" \
  "$build/libimage_ffmpeg.dylib" >/dev/null
xcrun simctl spawn "$udid" "$build/abi_boundary_test" --quick
echo "PASS: exact $target artifact on simulator $udid"
