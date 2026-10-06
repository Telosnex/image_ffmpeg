# Native libraries

Each native target gets one self-contained shim library. Homebrew, CocoaPods,
Gradle native dependencies, and a system FFmpeg installation are not used at
consumer build time or runtime.

`prebuilt.json` pins the library of each target by SHA-256 and names the
GitHub release that holds it. The workflow
`.github/workflows/native_release.yml` writes it: it runs `hook/build.dart` in
mode source for every target, uploads the libraries, and records the runner
and toolchain of each target. The hook uses the release only when the package
sources match its source key (`dart run native_prebuilt:key`). Check the
release with `dart run native_prebuilt:check`.

## Source pins

- FFmpeg `d32b387f2b0a484599d4587d651891f0c63c4238` (`n9.0`)
- libaom `10aece4157eb79315da205f39e19bf6ab3ee30d0` (`v3.12.1`)
- zlib `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf` (`v1.3.1`)
- native/Web build profile `9`

The reduced profile contains only libavformat, libavcodec, libavutil and
libswscale functionality needed by the image shim. It disables programs,
networking, devices, filters, assembly, runtime CPU detection, GPL and nonfree
components. libaom is decoder-only for AVIF. zlib supplies PNG compression.
Both are statically included. Profile 9 enables FFmpeg's native animated-WebP
demuxer/decoder and its required VP8 decoder from the official `n9.0` release.
Every build requires the exact peeled release commit above.

Libraries expose only the versioned `image_ffmpeg_*` shim ABI. Upstream symbols
are hidden with an exported-symbol list, ELF version script, or Windows module
definition. Licenses and notices are in the package `LICENSE`, in the
Flutter multi-license format.

## Matrix

| Target | Minimum | Release build |
|---|---|---|
| Android armv7, arm64, x64 | API 24 | ubuntu-22.04, NDK 28.2.13676358 |
| iOS arm64 device | iOS 13 | macos-15, Xcode |
| iOS arm64, x64 simulator | iOS 13 (arm64: 14) | macos-15, Xcode |
| Linux arm64, x64 | glibc 2.31 | Debian 11 container, GCC 10 |
| macOS arm64, x64 | macOS 12 | macos-15, Xcode |
| Windows x64 | Windows 10 | Debian 11 container, MinGW-w64 GCC 10 |
| Windows arm64 | Windows 10 UCRT | Debian 12 container, llvm-mingw 20260922 |

`prebuilt.json` has the exact toolchain of each target. The Browser Wasm
module is in `lib/web/`; `manifest.json` pins it and the source commits
(`dart run tool/verify_artifacts.dart`).

Unsupported target tuples fail in the build hook rather than silently shipping
an ABI scaffold without FFmpeg.

## Reproduction

```bash
tool/fetch_native_sources.sh

# Apple and Android (on macOS):
tool/build_native_artifact.sh macos-arm64
tool/build_native_artifact.sh ios-arm64-iphoneos
tool/build_native_artifact.sh android-arm64

# The Debian 11 Linux and MinGW Windows builds of the release workflow:
tool/build_native_linux_docker.sh linux-x64
tool/build_native_linux_docker.sh linux-arm64
tool/build_native_windows_docker.sh windows-x64

# Debian 12 plus SHA-256-pinned llvm-mingw 20260922 (GCC has no Windows arm64):
tool/build_native_windows_docker.sh windows-arm64
```

The libraries go to `build/native_artifacts/<target>/`. The hook runs the same
script with paths outside the package.

The Windows arm64 DLL imports only system DLLs: KERNEL32, bcrypt, and the
Universal C Runtime API sets present on Windows 10 and later. Wine cannot run
it; verify it on a Windows arm64 host by building
`tool/support/abi_boundary_test.c` with the same llvm-mingw release against an
import library generated from `src/exports_windows.def`, running it beside the
DLL, then running `dart test` in the package and `native_test` with a
`windows_arm64` Dart SDK.

`tool/build_native_artifact.sh` lists every direct target. Fetching verifies
immutable source commits. Building verifies architecture, exported symbols and
runtime dependency closure before printing the SHA-256 of the library.

Because FFmpeg is statically included inside the final shim library, downstream
binary distributors must review LGPL requirements. The corresponding source
revisions and complete relink scripts are recorded above; retain them with any
distributed binary.
