# Image format fixtures

This corpus was bootstrapped from Telosnex's
`test/assets/image_formats` format/golden suite so `image_ffmpeg` remains
independently testable. It covers JPEG, PNG/APNG, GIF, BMP, TIFF, ICO, WebP,
PSD, and AVIF.

The original `test_animated.*` files contained only one frame. APNG, GIF, and
WebP were replaced with genuine two-frame files (the volcano plus a horizontally
flipped second frame). Animated formats are expected to return the first frame.
APNG, GIF, and animated WebP all have positive first-frame decode coverage.
APNG's advertised frame-count assertion is retained as skipped because the
lightweight probe does not populate `nb_frames` from the `acTL` chunk. The
reduced GIF and animated-WebP demuxers likewise decode the first frame correctly
but do not advertise a total frame count.

Goldens are lossless PNG containers around expected RGBA results. The animated
WebP golden was independently decoded from frame zero with ImageMagick 7.1.1-47
and exactly matches `image_ffmpeg`; the remaining goldens establish the
reviewed package regression contract. They are deliberately viewable in
ordinary image tools. Tests compare premultiplied
RGBA values, so invisible RGB beneath zero alpha does not cause false failures.
On a mismatch, the native suite writes `actual`, `expected`, and amplified
`diff_x8` PNGs under `native_test/test/failures/image_formats`.

After intentionally accepting a decoder-output change, regenerate package
regression goldens from the linked native harness and review the resulting PNG
diff before committing:

```bash
cd native_test
dart run bin/update_image_format_goldens.dart
dart test test/image_formats_golden_test.dart
```

The updater intentionally preserves the independent animated-WebP reference.
Regenerate that reference from the package root with:

```bash
magick 'test/fixtures/image_formats/sources/test_animated.webp[0]' \
  -alpha on -depth 8 \
  'PNG32:test/fixtures/image_formats/goldens/verify_test_animated_webp.png'
```

The native harness uses the same SHA-256-verified reduced artifact bundled for
production consumers; no system FFmpeg installation is involved. The browser
corpus suite repeats metadata, full-resolution golden, and fit-within geometry
checks for every curated format through the production Worker/Wasm backend.
