# Pinned native artifacts

These are the production code assets selected by `hook/build.dart`. Each is one
self-contained shim library; Homebrew, CocoaPods, Gradle native dependencies,
and a system FFmpeg installation are not used at consumer build time or
runtime.

## Source pins

- FFmpeg `db69d06eeeab4f46da15030a80d539efb4503ca8` (`n7.1.1`)
- libaom `10aece4157eb79315da205f39e19bf6ab3ee30d0` (`v3.12.1`)
- zlib `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf` (`v1.3.1`)
- native build profile `6`

The reduced profile contains only libavformat, libavcodec, libavutil and
libswscale functionality needed by the image shim. It disables programs,
networking, devices, filters, assembly, runtime CPU detection, GPL and nonfree
components. libaom is decoder-only for AVIF. zlib supplies PNG compression.
Both are statically included.

Artifacts expose only the versioned `image_ffmpeg_*` shim ABI. Upstream symbols
are hidden with an exported-symbol list, ELF version script, or Windows module
definition. Licenses and notices are under `licenses/`.

## Matrix

| Target | Minimum | SHA-256 |
|---|---|---|
| Android armv7 | API 24 | `7d7cb790cd2ae13cd2a3b4015a51f8a8c4dfc0f7402d4208b822ab5dce31b4ac` |
| Android arm64 | API 24 | `c84a48e61eeb0b42fe2471fcf0b53abebae6e0144e25819c442565a1a63c28e3` |
| Android x64 | API 24 | `a1cca5cda0296b1feb535375cb73d330a482c6f629fb3e55ad1d2aa7b6182ab6` |
| iOS arm64 device | iOS 13 | `042258845f6dc4c40ab43e28364884b50b3259223560cf4393978d6b6a6b61bc` |
| iOS arm64 simulator | iOS 14 | `98ce5ebd6a31ca12cf62f8868c38735d084ead52a4e93bbf1a7e50fb4fdb35b4` |
| iOS x64 simulator | iOS 13 | `73c0ac448acd16562864769dfc75d2859aed70d6a381ca1afcf87c6dba2502c6` |
| Linux arm64 | glibc 2.31 | `30008a5b2606d572c6c55aa2a1463482a8f95856bfade9026b6af11e77c48772` |
| Linux x64 | glibc 2.31 | `ebfdb864af1510e20a67d77972ce492cc9525c548dec7b2571cded80e78130f6` |
| macOS arm64 | macOS 12 | `d5cf227dabcc3abab0e02842e33314c0d727befda462e2567bb0df8bda1c3cad` |
| macOS x64 | macOS 12 | `106b395f5258c06956819979d92676346405437467c9866c05f87cd7f3399351` |
| Windows x64 | Windows 10 | `99b9f6a1b29b879135e11d4f8f88dc85af29f5ceebb8bbbe38923d120a0c244f` |

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
