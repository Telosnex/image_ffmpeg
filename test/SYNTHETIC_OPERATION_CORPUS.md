# Synthetic operation corpus v1

This generated suite complements—never replaces—the 340-file upstream corpus
and ImageMagick/reviewed PNG references. Real codec inputs remain the primary
pixel oracle. These recipes isolate package-owned geometry, ownership, row
layout, and operation-order semantics that opaque files express poorly.

## Coverage

Twenty-one stable `v1/` recipes cover:

- independently encoded PNGs with prime dimensions;
- RGBA encoder planes with 7/13/29 bytes of poisoned row padding;
- top-left, bottom-right, one-pixel, and prime-interior crops;
- edge, one-pixel, opaque, and transparent hidden-RGB fills;
- landscape/portrait deterministic box averaging with both alpha modes;
- exact unchanged PNG passthrough;
- compound crop + fit-within scaling at an integer-rounding boundary;
- transparent JPEG compositing onto an explicit background.

The source planes are generated from fixed xorshift seeds. Alpha-zero pixels
retain nonzero RGB to catch accidental premultiplication or hidden-channel loss.
PNG sources come from the separately pinned pure-Dart `image` implementation.
Lossless operations are compared byte-for-byte with pure-Dart crop/fill/box
oracles. A curated malformed subset additionally locks `NOT_IMAGE`, `DECODE`,
and `UNSUPPORTED` distinctions.

Case IDs include a major recipe version. Threshold or acquisition changes that
invalidate expectations require `v2`, not silent golden movement.

## Reproduce

```bash
dart run tool/render_synthetic_operation.dart --list
dart run tool/render_synthetic_operation.dart \
  v1/crop-bottom-right /tmp/image_ffmpeg_case
```

The output directory contains `source.png`, `actual.png`, and—where an
independent exact oracle exists—`expected.png` plus an 8× amplified channel
difference image.

The same suite executes through VM/FFI, Chrome dart2js, Chrome dart2wasm, and
Safari dart2js.
