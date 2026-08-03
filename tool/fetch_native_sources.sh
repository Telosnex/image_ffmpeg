#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ffmpeg_commit=db69d06eeeab4f46da15030a80d539efb4503ca8
aom_commit=10aece4157eb79315da205f39e19bf6ab3ee30d0
zlib_commit=51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf

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

  rm -rf "$destination"
  git clone --filter=blob:none --no-checkout "$url" "$destination"
  git -C "$destination" fetch --depth 1 origin "$commit"
  git -C "$destination" checkout --detach "$commit"
  local actual
  actual="$(git -C "$destination" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || {
    echo "$name checkout verification failed: $actual" >&2
    exit 1
  }
  echo "Fetched $name at $commit"
}

fetch_at_commit FFmpeg https://github.com/FFmpeg/FFmpeg.git \
  "$ffmpeg_commit" "$root/third_party/ffmpeg"
fetch_at_commit libaom https://aomedia.googlesource.com/aom \
  "$aom_commit" "$root/third_party/aom"
fetch_at_commit zlib https://github.com/madler/zlib.git \
  "$zlib_commit" "$root/third_party/zlib"
