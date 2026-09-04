## 0.0.1

- Remove unreleased JPEG-only Dart/C compatibility aliases and replace the
  `_ex` encoder with one canonical ABI 5 JPEG operation.
- Give all boundary-crossing Dart enums explicit checked wire values rather
  than relying on declaration-order `.index` coupling.
- Extend the production manifest to lock all 11 native artifacts plus the
  Worker, loader, Emscripten module, Wasm, source pins, and profile.
- Add a direct C ownership/security corpus with 6,144 deterministic malformed
  calls and run it under AddressSanitizer and UndefinedBehaviorSanitizer.
- Runtime-test exact committed artifacts on macOS arm64/x64, iOS Simulator,
  Android, Linux arm64/x64, and Windows/Wine.
- Add 21 versioned synthetic operation recipes covering prime dimensions,
  poisoned row padding, hidden RGB, exact crop/fill edges, box averaging,
  passthrough, scaling rounding, JPEG composition, and precise malformed
  statuses, with a case-ID renderer for actual/expected/diff images.
- Make production Web builds fail when pinned reduced FFmpeg/libaom inputs are
  absent; scaffold Wasm can no longer be emitted accidentally.
- Add fused `ImageFfmpeg.fillRectangle` decode/fill/encode for hot screenshot
  masking paths without round-tripping full RGBA buffers through Dart.
- Replace the resource-handle-shaped `load()`/`dispose()` API with lazy static
  operations. Browser Worker/Wasm resources are package-managed and live for
  the page lifetime instead of being repeatedly initialized and destroyed.
- Add deterministic integer-only box-average decode with configurable alpha
  handling. POSIX native targets fold completed RGBA rows immediately and
  discard their scratch pages, avoiding a resident full-resolution RGBA image.
- Add a versioned, fixed-width C shim ABI.
- Bundle SHA-256-verified reduced FFmpeg native code assets for Android
  armv7/arm64/x64, iOS arm64 device and arm64/x64 simulator, Linux arm64/x64,
  macOS arm64/x64, and Windows x64 without a system FFmpeg dependency.
- Add reproducible immutable-commit builds for the official FFmpeg 9.0
  release, decoder-only libaom 3.12.1, and zlib 1.3.1, with
  constrained exports and dependency checks.
- Decode static and animated WebP, returning the first animation frame.
- Normalize deprecated full-range `YUVJ*` frames before scaling and explicitly
  preserve JPEG color range, eliminating libswscale's deprecated-pixel-format
  warning without suppressing diagnostics.
- Add native FFI and browser WebAssembly backends behind one async API.
- Connect the browser backend to a module Worker with request IDs, mapped
  errors, and transferable input/output buffers.
- Bundle the Worker, Emscripten adapter, generated JavaScript module, and Wasm
  binary automatically in Flutter web applications; expose
  `ImageFfmpegWeb.workerUri` for plain-Dart/custom hosting.
- Cover the browser backend in real Chrome under dart2js and Dart2Wasm.
- Add unattended real-Safari dart2js coverage with a package:test launcher that
  bypasses Safari's local-file confirmation dialog.
- Mirror the complete 439-test native conformance matrix through Chrome dart2js,
  Chrome Dart2Wasm, and Safari dart2js, including 340 source fixtures,
  malformed inputs, metadata/scaling checks, and pixel references.
- Add FFmpeg vendoring and Wasm build scripts.
- Implement byte-based image probing, first-frame decode, fit-within area
  scaling, and RGBA output through libavformat, libavcodec, and libswscale.
- Include JPEG, PNG/APNG, WebP, GIF, BMP, TIFF, AVIF, PSD, and ICO in the
  reduced Wasm build.
- Decode AVIF through pinned, decoder-only libaom and compose auxiliary alpha
  images into RGBA.
- Decode flattened PSD composites and select the largest ICO image, including
  classic BMP-backed ICO transparency masks.
- Encode RGBA8888 pixels as JPEG with configurable quality, 4:2:0/4:4:4
  chroma, and alpha-compositing background, or PNG with configurable
  compression and preserved alpha on native and Wasm.
- Add metadata-only image probing for format, coded/display dimensions, EXIF
  orientation, frame-count, and alpha hints.
- Add fused first-frame decode, EXIF orientation, crop, fit-within resize, and
  JPEG/PNG transcode with optional unchanged passthrough.
- Add native and Wasm benchmarks for the 4000×5000 progressive-JPEG fixture.
