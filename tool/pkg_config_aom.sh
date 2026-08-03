#!/usr/bin/env bash
set -euo pipefail

: "${AOM_PREFIX:?AOM_PREFIX must point to the reduced libaom installation}"

if [[ "${1:-}" == --version ]]; then
  echo 1.8.0
  exit 0
fi
if [[ "${1:-}" == --atleast-pkgconfig-version ]]; then
  exit 0
fi

is_aom_query=false
for argument in "$@"; do
  [[ "$argument" == aom ]] && is_aom_query=true
done
$is_aom_query || exit 1

for argument in "$@"; do
  case "$argument" in
    --exists|--print-errors|--static|aom|'>'|'>='|[0-9]*) ;;
    --cflags|--cflags-only-I)
      echo "-I$AOM_PREFIX/include"
      exit 0
      ;;
    --libs)
      echo "-L$AOM_PREFIX/lib -laom"
      exit 0
      ;;
    --variable=includedir)
      echo "$AOM_PREFIX/include"
      exit 0
      ;;
    --modversion)
      echo "3.12.1"
      exit 0
      ;;
  esac
done

# --exists has no output; reaching here means the pinned installation exists.
test -f "$AOM_PREFIX/lib/libaom.a"
