#!/usr/bin/env bash
# Authoritative package gate. CI should call this instead of duplicating lists.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

browser_tests=(
  test/image_ffmpeg_web_bad_worker_test.dart
  test/image_ffmpeg_web_test.dart
  test/image_ffmpeg_web_pool_test.dart
  test/image_ffmpeg_web_serial_pool_test.dart
  test/image_ffmpeg_web_corpus_test.dart
  test/image_ffmpeg_synthetic_operation_test.dart
)

dart analyze
dart run tool/verify_artifacts.dart
dart run tool/update_browser_corpus_manifest.dart --check
dart test -r compact
if [[ -d native_test ]]; then
  (
    cd native_test
    # Native-asset hooks do not replace an already materialized dylib whose ABI
    # changed in-place. The conformance package must consume today's manifest.
    rm -rf .dart_tool
    dart pub get >/dev/null
    dart test -r compact
  )
fi

dart test -p chrome --compiler dart2js -j 1 -r compact "${browser_tests[@]}"
# Every dart2wasm file owns a test Wasm module plus codec Wasm Workers. Keep
# process-memory pressure from hiding results as generic browser disconnects.
dart test -p chrome --compiler dart2wasm -j 1 -r compact "${browser_tests[@]}"

if [[ "$(uname -s)" == Darwin && "${IMAGE_FFMPEG_SKIP_SAFARI:-0}" != 1 ]]; then
  dart test -p safari --compiler dart2js -j 1 -r compact "${browser_tests[@]}"
fi

if [[ "$(uname -s)" == Darwin ]]; then
  tool/test_macos_artifacts.sh
  tool/test_native_sanitizers.sh
fi

if [[ "${IMAGE_FFMPEG_FULL_RUNTIME_MATRIX:-0}" == 1 ]]; then
  tool/test_linux_artifact_docker.sh linux-arm64
  tool/test_linux_artifact_docker.sh linux-x64
  tool/test_windows_artifact_wine.sh
  if [[ "$(uname -s)" == Darwin ]]; then
    tool/test_ios_simulator_artifact.sh
    tool/test_android_artifact.sh
  fi
fi
