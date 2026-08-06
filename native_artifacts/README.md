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
| Android armv7 | API 24 | `847f743fc1d1f179089ef9807686db82b1a935c7eeca002660f040ea1de54dba` |
| Android arm64 | API 24 | `edd317b6e9d548c83a23658310850b230fc117b1569b9f587b6680589cc012e0` |
| Android x64 | API 24 | `0b4786bb286218c346bb7553e5ca2b0b81ae816533ce5664232086bbe2e43a5f` |
| iOS arm64 device | iOS 13 | `8b5d24f88082cab70a32bbe3bfa4616676d46b889f4d2edf88d109b480a845c4` |
| iOS arm64 simulator | iOS 14 | `9c83362b9f62f396790473ac1d542dd1a8ec2491b80f87ad25155da84d5cb4c3` |
| iOS x64 simulator | iOS 13 | `861937a3b789e586314a4f0825110b8c726d0c121f7e7131436dd8e1d9ebf1ce` |
| Linux arm64 | glibc 2.31 | `e662bcd493fba95c157378cd462f8f779de74e1df33f59900cc0bd07c9d2715b` |
| Linux x64 | glibc 2.31 | `fd9e7e06bbcc0ed5b4765a4e7fb54ae9886bdfdf7ee2daeaeee84dc4b96ae7bf` |
| macOS arm64 | macOS 12 | `d056decbfff2ec6068b6b58382ca7591d70f8ad026fcf405d7fd64512e8e2431` |
| macOS x64 | macOS 12 | `f40f9d6828321089383cb9214f66a6f88025876379fe2c73ec73fc293deb669d` |
| Windows x64 | Windows 10 | `f1419b2b7501dd56a0766c143dc18efc792a785dfc9a1afa2316b0dc81543b4b` |

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
