# Pinned native artifacts

These are the production code assets selected by `hook/build.dart`. Each is one
self-contained shim library; Homebrew, CocoaPods, Gradle native dependencies,
and a system FFmpeg installation are not used at consumer build time or
runtime.

## Source pins

- FFmpeg `d32b387f2b0a484599d4587d651891f0c63c4238` (`n9.0`)
- libaom `10aece4157eb79315da205f39e19bf6ab3ee30d0` (`v3.12.1`)
- zlib `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf` (`v1.3.1`)
- native build profile `8`

The reduced profile contains only libavformat, libavcodec, libavutil and
libswscale functionality needed by the image shim. It disables programs,
networking, devices, filters, assembly, runtime CPU detection, GPL and nonfree
components. libaom is decoder-only for AVIF. zlib supplies PNG compression.
Both are statically included. Profile 8 enables FFmpeg's native animated-WebP
demuxer/decoder and its required VP8 decoder from the official `n9.0` release.
Every build requires the exact peeled release commit above, and the full image
corpus is run against the resulting bytes.

Artifacts expose only the versioned `image_ffmpeg_*` shim ABI. Upstream symbols
are hidden with an exported-symbol list, ELF version script, or Windows module
definition. Licenses and notices are under `licenses/`.

## Matrix

| Target | Minimum | SHA-256 |
|---|---|---|
| Android armv7 | API 24 | `3fca75244de76e5b37e292c8b06b1bc0f33c3d12dc36add7022e8e3c2c7ab984` |
| Android arm64 | API 24 | `dc9321b1be39c29364939d807d399e2fe2e47915a28ab8b897d3150e27636447` |
| Android x64 | API 24 | `9871a9a94645db50b609fa062473164412857e37f053a5eab2ba2f40c0816e5c` |
| iOS arm64 device | iOS 13 | `f1975bc3566e9e6aa8631ecdd83099eff8af1c4c805cb9718050e6f5a3219121` |
| iOS arm64 simulator | iOS 14 | `7183389bbbb95042aae1c778639d39103ac62156e4783a4c4ca4e945b51ad256` |
| iOS x64 simulator | iOS 13 | `217a7f37e61a129f8daa60e79de00b14ccecff957bcac2e2cbb32f7954f6fe58` |
| Linux arm64 | glibc 2.31 | `0362e680877b1388db677d7e7eff9bea99be66d75bd65c486d095246a7464804` |
| Linux x64 | glibc 2.31 | `790413e32e10edf9de93f62ebc74bb5b2f6fd5f97d1b2e651350020f88754333` |
| macOS arm64 | macOS 12 | `ae3f16e61fe84004eef43ceff690cce31baded4d850fd41874464c3bedb1d1d4` |
| macOS x64 | macOS 12 | `dcf4f72e0322e11862c8747fee3453dec5162f46d1308d18e36d669d27085c07` |
| Windows x64 | Windows 10 | `5a4db497998ef18f50d3251d558dfb6079cbfd558074f5d41cba7fd846596115` |

Unsupported target tuples fail in the build hook rather than silently shipping
an ABI scaffold without FFmpeg.

## Reproduction

```bash
tool/fetch_native_sources.sh

# Apple and Android (on macOS):
tool/build_native_artifact.sh macos-arm64
tool/build_native_artifact.sh ios-arm64-iphoneos
tool/build_native_artifact.sh android-arm64

# Reproducible Debian 11 Linux and MinGW Windows builds:
tool/build_native_linux_docker.sh linux-x64
tool/build_native_linux_docker.sh linux-arm64
tool/build_native_windows_docker.sh windows-x64
```

`tool/build_native_artifact.sh` lists every direct target. Fetching verifies
immutable source commits. Building verifies architecture, exported symbols and
runtime dependency closure before printing the SHA-256 used by the hook. After
updating artifacts and `manifest.json`, verify every byte with:

```bash
dart run tool/verify_native_artifacts.dart
```

Because FFmpeg is statically included inside the final shim library, downstream
binary distributors must review LGPL requirements. The corresponding source
revisions and complete relink scripts are recorded above; retain them with any
distributed binary.
