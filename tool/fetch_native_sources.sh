#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# hook/build.dart sets IMAGE_FFMPEG_THIRD_PARTY to a directory outside the
# package.
third_party="${IMAGE_FFMPEG_THIRD_PARTY:-$root/third_party}"
ffmpeg_commit=946fcce07b6dcd0331c8cc609192aeff5e1924f8
aom_commit=b141d9c45db236335351c8a4b2a14b3ade27c937
zlib_commit=da607da739fa6047df13e66a2af6b8bec7c2a498

fetch_at_commit() {
  local name="$1"
  local url="$2"
  local commit="$3"
  local destination="$4"

  if [[ -d "$destination/.git" ]]; then
    local actual
    actual="$(git -C "$destination" rev-parse HEAD)"
    if [[ "$actual" == "$commit" ]]; then
      echo "$name already pinned at $commit"
      return
    fi
    echo "$name checkout has unexpected HEAD $actual; expected $commit" >&2
    echo "Remove $destination explicitly before replacing it." >&2
    exit 1
  fi
  if [[ -e "$destination" ]] &&
      [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Refusing to replace non-empty $destination" >&2
    exit 1
  fi

  # Fetch only the pinned commit into a temporary directory, then rename it,
  # so an interrupted fetch leaves no partial checkout at $destination.
  rm -rf "$destination"
  local partial="$destination.partial.$$"
  rm -rf "$partial"
  mkdir -p "$(dirname "$destination")"
  git init -q "$partial"
  git -C "$partial" remote add origin "$url"
  git -C "$partial" fetch -q --depth 1 origin "$commit"
  git -C "$partial" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  local actual
  actual="$(git -C "$partial" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || {
    echo "$name checkout verification failed: $actual" >&2
    rm -rf "$partial"
    exit 1
  }
  mv "$partial" "$destination"
  echo "Fetched $name at $commit"
}

fetch_at_commit FFmpeg https://github.com/FFmpeg/FFmpeg.git \
  "$ffmpeg_commit" "$third_party/ffmpeg"
fetch_at_commit libaom https://aomedia.googlesource.com/aom \
  "$aom_commit" "$third_party/aom"
fetch_at_commit zlib https://github.com/madler/zlib.git \
  "$zlib_commit" "$third_party/zlib"
