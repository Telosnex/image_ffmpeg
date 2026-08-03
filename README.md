# image_ffmpeg

A cross-platform image codec built on a reduced, pinned FFmpeg distribution
behind one Dart API:

```text
                         src/image_ffmpeg.h
                                │
              ┌─────────────────┴─────────────────┐
              │                                   │
      native code asset                    Emscripten module
         + dart:ffi                         + Web Worker
              │                                   │
              └────────── Future-based Dart API ──┘
```

Native builds bundle SHA-256-pinned artifacts for Android, iOS, Linux, macOS,
and Windows. Each artifact contains the stable shim plus an exact August 3,
2026 post-8.1 FFmpeg `master` snapshot, decoder-only libaom 3.12.1, and zlib
1.3.1. The snapshot includes FFmpeg's native animated-WebP decoder and is
pinned by commit rather than a moving branch. Consumers do not install FFmpeg,
Homebrew, CocoaPods, or Gradle native dependencies. Browsers use the same
reduced codec profile through a bundled WebAssembly module running off the UI
thread in a module Worker.

## API

```dart
final ffmpeg = await Ffmpeg.load();
print(ffmpeg.capabilities);

final info = await ffmpeg.probeImage(arbitraryBytes);

final image = await ffmpeg.decodeImage(
  arbitraryBytes,
  maxWidth: 96,
  maxHeight: 96,
);
final jpeg = await ffmpeg.encodeJpeg(
  image,
  quality: 90,
  chroma: JpegChroma.yuv444,
);
final png = await ffmpeg.encodePng(image, compressionLevel: 9);

// Keep the decoded RGBA intermediate inside native/Wasm memory.
final thumbnail = await ffmpeg.transcodeImage(
  arbitraryBytes,
  output: const ImageOutput.jpeg(
    quality: 80,
    chroma: JpegChroma.yuv420,
  ),
  maxWidth: 2048,
  maxHeight: 2048,
  applyOrientation: true,
  passthroughIfUnchanged: true,
);

await ffmpeg.dispose();
```

The API is asynchronous on every platform so native work can live on a helper
isolate and browser work can live in a Web Worker.

## Why a shim instead of generated FFmpeg bindings?

`src/image_ffmpeg.h` is a small, stable, fixed-width C ABI. It hides `AVFrame`,
`AVPacket`, allocator ownership, pixel-format negotiation, and FFmpeg version
differences. The same operation is exported natively and from Wasm:

```c
int32_t image_ffmpeg_decode_image_rgba(
    const uint8_t *input,
    uint32_t input_length,
    uint32_t max_width,
    uint32_t max_height,
    image_ffmpeg_image *output);
```

One coarse decode call performs format probing, first-frame decode, fit-within
scaling, RGBA conversion, and output allocation. JPEG and PNG encoding each use
one additional coarse call. `transcodeImage` fuses first-frame decode, EXIF
orientation, crop, fit-within scaling, and encode, so a potentially large RGBA
intermediate never crosses the FFI/Wasm boundary. That minimizes both calls and
memory traffic.

The image allow-list is JPEG, PNG/APNG, static and animated WebP, GIF, BMP,
TIFF, AVIF, PSD, and ICO; the reduced Wasm build includes the same codecs.
AVIF decoding uses a pinned, decoder-only libaom build and composes an
auxiliary alpha image into RGBA when present. PSD returns the flattened
composite image. ICO selects the largest embedded image (preferring higher bit
depth for ties) and applies classic BMP-backed icons' 1-bit AND transparency
mask. Other FFmpeg media inputs are rejected rather than silently treating a
video as an image. Unknown bytes return `FfmpegException` status `-6`;
recognized but unavailable formats and decode failures use distinct statuses.

RGBA8888 output can be encoded as JPEG or PNG. JPEG quality ranges from 1 to
100, supports either compact 4:2:0 or full-resolution 4:4:4 chroma, and
composites pixels onto a configurable `0xAARRGGBB` background because JPEG has
no alpha channel. PNG compression ranges from 0 to 9 and preserves alpha. Input
geometry is validated and capped at 100 million pixels.

`probeImage` returns coded and post-orientation display dimensions, image
format, EXIF orientation, advertised frame count, and an alpha hint without
materializing RGBA pixels. `transcodeImage` applies orientation before crop, so
crop coordinates match what a user sees. Scaling follows crop and never
upscales. Explicit `passthroughIfUnchanged` preserves an existing JPEG or PNG
when no transform is needed, avoiding generation loss and honoring the original
metadata and animation bytes.

Source images are capped at 100 million pixels and animated formats return
their first frame unless explicit unchanged passthrough preserves the original
file. Standalone `decodeImage` does not apply metadata orientation; fused
`transcodeImage` applies EXIF orientation from JPEG, PNG, WebP, and TIFF when
requested. AVIF grids and ICC color management are not currently applied.

## Browser platforms

Flutter web apps need no manual setup: the package declares its Worker,
JavaScript adapter, Emscripten module, and Wasm binary as package assets.
`flutter build web` places them under
`assets/packages/image_ffmpeg/web/`, and `Ffmpeg.load()` resolves that path
against the document base URI. This works with a non-root Flutter
`--base-href` as well as at `/`.

Plain Dart browser applications must serve the four sibling files from
`lib/web/` and configure their URL before loading:

```dart
FfmpegWeb.workerUri = Uri.parse('/vendor/image_ffmpeg/image_ffmpeg_worker.mjs');
final ffmpeg = await Ffmpeg.load();
```

Keep all four files together because the module Worker imports the loader and
Emscripten module relatively, and the Emscripten module locates its Wasm binary
relatively. They must be served over HTTP(S) with JavaScript/Wasm MIME types;
`file://` does not provide a usable module-Worker origin.

The dart2js application build is covered by real Chrome and Safari integration
tests; Dart2Wasm/WasmGC is covered in Chrome because `package:test` currently
runs Safari with dart2js. Encoded inputs are copied into transferable buffers
before dispatch so transferring them never detaches caller-owned Dart bytes.
Encoded and RGBA results are transferred back rather than structured-cloned.

## Native platforms

| Platform | Architectures | Minimum |
|---|---|---|
| Android | armv7, arm64, x64 | API 24 |
| iOS | arm64 device; arm64/x64 simulator | iOS 13 (arm64 simulator 14) |
| Linux | arm64, x64 | glibc 2.31 |
| macOS | arm64, x64 | macOS 12 |
| Windows | x64 | Windows 10 |

The build hook selects the target tuple, verifies the committed artifact's
SHA-256, and emits it as a bundled Dart code asset. Unsupported tuples fail at
build time rather than loading an FFmpeg-free scaffold. Exact source commits,
checksums, licenses, dependency-closure checks, and reproduction commands are
in [`native_artifacts/README.md`](native_artifacts/README.md).

## Current pieces

- `hook/build.dart`: verifies and bundles the target-native production asset.
- `ffigen.yaml`: generates native `@Native` bindings from the stable header.
- `lib/src/backend/backend_native.dart`: validates ABI, copies memory safely,
  and runs decode on a helper isolate.
- `lib/src/backend/backend_web.dart`: Worker client selected with a conditional
  import, including request routing, error mapping, and transferable buffers.
- `lib/web/image_ffmpeg_loader.mjs`: Emscripten linear-memory adapter for the
  same C ABI.
- `lib/web/image_ffmpeg_worker.mjs`: request/response Worker protocol with
  transferable input and output buffers.
- `lib/web/image_ffmpeg_module.{mjs,wasm}`: committed browser runtime bundled as
  Flutter package assets.
- `tool/build_web.sh`: builds the current C shim to Wasm.
- `tool/fetch_ffmpeg.sh`: fetches the pinned upstream source.
- `native_test/`: linked-FFmpeg format conformance suite with viewable PNG
  goldens and actual/expected/amplified-diff artifacts on failures.

## Development

```bash
dart pub get
dart run ffigen --config ffigen.yaml
dart test test/image_ffmpeg_test.dart
dart test -p chrome test/image_ffmpeg_web_test.dart
dart test -p chrome -c dart2wasm test/image_ffmpeg_web_test.dart
dart test -p safari test/image_ffmpeg_web_test.dart # macOS only
dart analyze
```

`dart_test.yaml` routes Safari through `tool/safari_test_launcher.sh`. The
wrapper extracts `package:test`'s loopback manager URL and sends the HTTP URL to
Safari through Launch Services, avoiding Safari's interactive **Confirm the
file to load** dialog for the temporary `redirect.html`. It remains alive for
the suite and closes only its test-manager tab afterward.

Run the native format corpus against the same pinned artifact shipped to
consumers:

```bash
cd native_test
dart pub get
dart test test/image_formats_golden_test.dart
dart test test/image_corpus_decode_test.dart
dart test test/image_corpus_reference_test.dart
dart test test/image_corpus_malformed_test.dart
```

Benchmark native FFmpeg on the 4000×5000 progressive-JPEG fixture:

```bash
cd benchmark
dart pub get
dart run bin/benchmark_wallpaper.dart [optional/input.jpg]
```

Build the reduced single-threaded FFmpeg WebAssembly libraries and module after
activating Emscripten:

```bash
source /Users/jpo/dev/emsdk/emsdk_env.sh
./tool/fetch_aom.sh
./tool/build_aom_web.sh
./tool/build_ffmpeg_web.sh
./tool/build_web.sh
node benchmark/benchmark_wallpaper_wasm.mjs [optional/input.jpg]
```

For a real browser run, link or copy the fixture to
`benchmark/wallpaper.jpg`, serve the package root, and open
`benchmark/benchmark_wallpaper_web.html` in Chrome. The final module is about
2.5 MiB with the pinned post-8.1 FFmpeg snapshot, libaom 3.12.1, the nine
decode formats listed above, and JPEG/PNG encoders.

Reproduce native artifacts from immutable source commits:

```bash
./tool/fetch_native_sources.sh
./tool/build_native_artifact.sh macos-arm64
./tool/build_native_linux_docker.sh linux-x64
./tool/build_native_windows_docker.sh windows-x64
```

See `tool/build_native_artifact.sh` for the complete Apple and Android target
matrix.

## Next milestones

1. Run the complete native fixture corpus against the browser backend; compare
   dimensions and pixel tolerances rather than assuming scaler bit identity.
2. Add configurable resource limits, broader metadata support, and ICC color
   management.
3. Add a persistent native helper isolate and reusable decoder contexts to
   distinguish codec time from setup time in repeated workloads.
4. Generalize the build/ABI generator into a reusable dual-target C-library
   template.

See [doc/PORTING_C_LIBRARIES.md](doc/PORTING_C_LIBRARIES.md) for the reusable
pattern.
