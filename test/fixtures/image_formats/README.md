# Image format fixtures

This corpus was bootstrapped from Telosnex's
`test/assets/image_formats` format/golden suite so `image_ffmpeg` remains
independently testable. It covers JPEG, PNG/APNG, GIF, BMP, TIFF, ICO, WebP,
PSD, and AVIF.

The original `test_animated.*` files contained only one frame. APNG, GIF, and
WebP were replaced with genuine two-frame files (the volcano plus a horizontally
flipped second frame). Animated formats are expected to return the first frame.
The animated WebP fixture is retained as a pinned expected failure because
FFmpeg 7.1 cannot decode its `ANIM`/`ANMF` chunks. APNG first-frame decode
works, but its advertised frame-count assertion is retained as skipped because
the lightweight probe does not populate `nb_frames` from the `acTL` chunk.
The reduced GIF image-pipe demuxer likewise decodes the first frame correctly
but does not advertise a total frame count.

Goldens are lossless PNG containers around `image_ffmpeg`'s RGBA result. They
are deliberately viewable in ordinary image tools. Tests compare premultiplied
RGBA values, so invisible RGB beneath zero alpha does not cause false failures.
On a mismatch, the native suite writes `actual`, `expected`, and amplified
`diff_x8` PNGs under `native_test/test/failures/image_formats`.

After intentionally accepting a decoder-output change, regenerate goldens from
the linked native harness and review the resulting PNG diff before committing:

```bash
cd native_test
dart run bin/update_image_format_goldens.dart
dart test test/image_formats_golden_test.dart
```

The native harness uses the same SHA-256-verified reduced artifact bundled for
production consumers; no system FFmpeg installation is involved.
