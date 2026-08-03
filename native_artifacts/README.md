# Pinned native artifacts

These are the production code assets selected by `hook/build.dart`. Each is one
self-contained shim library; Homebrew, CocoaPods, Gradle native dependencies,
and a system FFmpeg installation are not used at consumer build time or
runtime.

## Source pins

- FFmpeg `d3ad8a7fee6a647c6362e4a105d949282d50a98f` (August 3, 2026,
  post-`n8.1` `master` snapshot)
- libaom `10aece4157eb79315da205f39e19bf6ab3ee30d0` (`v3.12.1`)
- zlib `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf` (`v1.3.1`)
- native build profile `7`

The reduced profile contains only libavformat, libavcodec, libavutil and
libswscale functionality needed by the image shim. It disables programs,
networking, devices, filters, assembly, runtime CPU detection, GPL and nonfree
components. libaom is decoder-only for AVIF. zlib supplies PNG compression.
Both are statically included. Profile 7 additionally enables FFmpeg's native
animated-WebP demuxer/decoder and its required VP8 decoder.

There was no tagged FFmpeg release containing animated-WebP support when this
pin was selected. Using an unreleased snapshot carries more regression risk than
a stable release, so the branch name is never consumed at build time: every
build requires the exact commit above, and the full image corpus is run against
the resulting bytes.

Artifacts expose only the versioned `image_ffmpeg_*` shim ABI. Upstream symbols
are hidden with an exported-symbol list, ELF version script, or Windows module
definition. Licenses and notices are under `licenses/`.

## Matrix

| Target | Minimum | SHA-256 |
|---|---|---|
| Android armv7 | API 24 | `3f1d880e4670938f8b08c4466d85ddcfdecd1a8485a1a2912449ca2a319f526f` |
| Android arm64 | API 24 | `8eb615265bcd4c22d35d7521b9124dddda67fe1033b4c0d2ae19790f0f919651` |
| Android x64 | API 24 | `a370e01d4ae4fd9f9aa1ec8c8cd430131096dc917c7c4433b238398eea16fb90` |
| iOS arm64 device | iOS 13 | `5e7e04c5d1b06fddcb4f8a46621972ccd7544a1128b88d713701e3c20911944b` |
| iOS arm64 simulator | iOS 14 | `ae4d3c1e553b2497936ac5966693d6517f5e34205a7c84927931b65a10c75b12` |
| iOS x64 simulator | iOS 13 | `b3ac97f7ab302f4dfff58e5a449b068e3cb62d22d47d15195ecf33ce86c2fcf5` |
| Linux arm64 | glibc 2.31 | `352aad89fbe2add9c9377ceb22228e5f54b759a6111ef56ba9b8082fd14438ae` |
| Linux x64 | glibc 2.31 | `621e3a7e2fe25cccc05e3d93e619cbaefc392f90d362ab59ec67f91883a20578` |
| macOS arm64 | macOS 12 | `2ad630de460a4aa5f96f3ced08e5af117db8dad828e61448e1cb5ba35ae8af82` |
| macOS x64 | macOS 12 | `12c3f33ab171aa2780264ec488c3d4da377e9eff2097ef46262099419649930a` |
| Windows x64 | Windows 10 | `cef653f4b85bfd1c6a0da1b9e89d5324368ff650c19d92d0c9e861243e3cc3df` |

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
