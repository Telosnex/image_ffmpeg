#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image_repo="${1:-$repo_root/../image}"
source_root="$image_repo/test/_data"
destination="$repo_root/test/fixtures/image_corpus/image"

if [[ ! -d "$source_root" ]]; then
  echo "image test corpus not found at $source_root" >&2
  echo "usage: $0 [/path/to/image]" >&2
  exit 1
fi

mkdir -p "$destination"
for directory in bmp gif ico jpg png tiff webp; do
  rm -rf "$destination/$directory"
  cp -R "$source_root/$directory" "$destination/$directory"
done
cp "$image_repo/LICENSE" \
  "$repo_root/test/fixtures/image_corpus/IMAGE_PACKAGE_LICENSE"

count="$(find "$destination" -type f | wc -l | tr -d ' ')"
if [[ "$count" != 345 ]]; then
  echo "Expected 345 fixture files after update, found $count." >&2
  echo 'Review the upstream corpus and update tests/documentation intentionally.' >&2
  exit 1
fi

(
  cd "$repo_root"
  dart run tool/update_browser_corpus_manifest.dart
)

echo "Copied $count files from $image_repo."
