#!/usr/bin/env bash
# Builds a Windows library in the Debian container of the release workflow.
# No Windows SDK or Visual Studio is required. Keep the images in sync with
# .github/workflows/native_release.yml.
#
# windows-x64: Debian 11 amd64 with MinGW-w64 GCC.
# windows-arm64: Debian 12 with the pinned llvm-mingw release of
# tool/install_build_toolchain.sh. The container runs on the Docker host's
# native architecture; the release workflow uses amd64.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
case "$target" in
  windows-x64|windows-arm64) ;;
  *) echo "Usage: $0 <windows-x64|windows-arm64>" >&2; exit 64 ;;
esac

command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

if [[ "$target" == windows-x64 ]]; then
  platform=linux/amd64
  image='debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a'
else
  # Platform manifests from debian:bookworm-slim index
  # sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241.
  case "$(docker info --format '{{.Architecture}}')" in
    aarch64|arm64)
      platform=linux/arm64
      image='debian@sha256:817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0'
      ;;
    x86_64|amd64)
      platform=linux/amd64
      image='debian@sha256:362e64223cc0da95422b3b13c045186fc0a81250e765d31c025fbddf257f6143'
      ;;
    *) echo 'Unsupported Docker host architecture.' >&2; exit 1 ;;
  esac
fi

docker run --rm --platform "$platform" \
  -v "$root:/workspace" \
  -w /workspace \
  -e IMAGE_FFMPEG_BUILD_JOBS="${IMAGE_FFMPEG_BUILD_JOBS:-}" \
  "$image" \
  bash -c "
    set -euo pipefail
    tool/install_build_toolchain.sh $target
    export PATH=/opt/llvm-mingw/bin:\$PATH
    [[ -n \"\$IMAGE_FFMPEG_BUILD_JOBS\" ]] || unset IMAGE_FFMPEG_BUILD_JOBS
    tool/fetch_native_sources.sh
    tool/build_native_artifact.sh $target
  "
