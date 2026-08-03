#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/third_party/ffmpeg"
revision=d3ad8a7fee6a647c6362e4a105d949282d50a98f

if [[ -d "$destination/.git" ]]; then
  actual="$(git -C "$destination" rev-parse HEAD)"
  [[ "$actual" == "$revision" ]] || {
    echo "FFmpeg checkout has $actual; expected pinned $revision" >&2
    exit 1
  }
  echo "FFmpeg already pinned at $revision"
  exit 0
fi
if [[ -e "$destination" ]] &&
    [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Refusing to replace non-empty $destination" >&2
  exit 1
fi

rm -rf "$destination"
git clone --filter=blob:none --no-checkout \
  https://github.com/FFmpeg/FFmpeg.git "$destination"
git -C "$destination" fetch --depth 1 origin "$revision"
git -C "$destination" checkout --detach "$revision"
[[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
echo "Fetched FFmpeg at $revision"
