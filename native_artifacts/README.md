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
| Android armv7 | API 24 | `61f76b4442d17df675cd0195edacff9c3225842e5ff2af203902c3b149c69a90` |
| Android arm64 | API 24 | `be5c7fcca8a49fda51cde52ecabdbeffdabca6fbd9156bbf3317b79d8700a4ce` |
| Android x64 | API 24 | `ebcde121da111f0499e337647713aa47d129b6190e1fd7f95ba49a977cd70cce` |
| iOS arm64 device | iOS 13 | `9607f60c2f5c67e51945e95e81a7abc9fb7e7984d6d4306baf57ac04613a8da0` |
| iOS arm64 simulator | iOS 14 | `8daba6bfff0767f9e7549e46b0e9286f682115896dc6bfdebdb5f0afda85bc3f` |
| iOS x64 simulator | iOS 13 | `56e12bcf47d7b477a96e2688f6c122e6c0a3a5a17148545dd8d23790d6df19b6` |
| Linux arm64 | glibc 2.31 | `c2d107cbe85320c08539a08233ca9a7f1445d825257c0cf9c09aec98a66f78bd` |
| Linux x64 | glibc 2.31 | `fe88327de76dd6ee5880ac4ec12da108bb4d163248cb92bb0a73222ca000431a` |
| macOS arm64 | macOS 12 | `53d256f5f2016db4078873f420acb22aef330b4172f0c6792a68c0fa21688df7` |
| macOS x64 | macOS 12 | `8ecbca3a3f58d9919571b64c2240a4dcc256d0b78bebf2066cd81d7775ea1698` |
| Windows x64 | Windows 10 | `452e08dc19af7d5e6429ce41a8b14522259ca3b49597d89a70fe9c0dceff5d1b` |

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
