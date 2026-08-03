## 0.0.1

- Add a versioned, fixed-width C shim ABI.
- Bundle SHA-256-verified reduced FFmpeg native code assets for Android
  armv7/arm64/x64, iOS arm64 device and arm64/x64 simulator, Linux arm64/x64,
  macOS arm64/x64, and Windows x64 without a system FFmpeg dependency.
- Add reproducible immutable-commit builds for an August 3, 2026 post-8.1
  FFmpeg `master` snapshot, decoder-only libaom 3.12.1, and zlib 1.3.1, with
  constrained exports and dependency checks.
- Decode static and animated WebP, returning the first animation frame.
- Add native FFI and browser WebAssembly backend seams behind one async API.
- Add an Emscripten linear-memory adapter and Web Worker protocol.
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
