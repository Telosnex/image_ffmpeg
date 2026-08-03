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
| Android armv7 | API 24 | `f220fd67e0a332e0721583f6da1f5d35f8eb30a0fce1c31a30fca8326e09d3d8` |
| Android arm64 | API 24 | `1caf289b9d0543c9527c7b7b7cd8ac2247e05974c3aad8ca312d1dd74f3a7670` |
| Android x64 | API 24 | `979376226cb6d2011f517b13f5e6e22aa2c3ec13ec47e70856213071b607cdc2` |
| iOS arm64 device | iOS 13 | `4d6f62032f3e0bee8c701b45981ab087c8b9aff95b5a2dbed19b6b97cc8ff299` |
| iOS arm64 simulator | iOS 14 | `46e2e9f60f1c232a7081244199f168a746f172ae167c6c446208355711f54909` |
| iOS x64 simulator | iOS 13 | `657eb78db8bfca922c265bbf9b2e28401ff30e4196516297dde3c86f6b00cde1` |
| Linux arm64 | glibc 2.31 | `f663e670b3ef1644c0b3958928cf5ae0bf13a86f5be2ca5328719a8e734c0efe` |
| Linux x64 | glibc 2.31 | `d2767792c0153373334dfc0ce9cc10558eb77e395691ae50929381184e3ccfea` |
| macOS arm64 | macOS 12 | `0b5ef80ca191bc939634be8fbc1e6c5c03a9d02d9eea894e04715b926a09a64f` |
| macOS x64 | macOS 12 | `2f09368cb8e6bcd7b65a1d3b9fac149f3425c23b5e39a7f500c37e5e8bd76ebd` |
| Windows x64 | Windows 10 | `3890c5ab69875b38aa8d20154cde415c392d383eb71628a7a073af86c0d3e58a` |

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
