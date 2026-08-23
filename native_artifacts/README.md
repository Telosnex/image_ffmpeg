# Pinned production artifacts

These are the production code assets selected by `hook/build.dart`. Each is one
self-contained shim library; Homebrew, CocoaPods, Gradle native dependencies,
and a system FFmpeg installation are not used at consumer build time or
runtime.

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
Every build requires the exact peeled release commit above, and the full image
corpus is run against the resulting bytes.

Artifacts expose only the versioned `image_ffmpeg_*` shim ABI. Upstream symbols
are hidden with an exported-symbol list, ELF version script, or Windows module
definition. Licenses and notices are under `licenses/`.

## Matrix

| Target | Minimum | SHA-256 |
|---|---|---|
| Android armv7 | API 24 | `c3b5da0272f44ea6c9a549faa6d63c7587e5d448ca88b154f32328633734e6a7` |
| Android arm64 | API 24 | `3a7f9513ecb779c3583411b0ca1365508f1f6ada72365f9fc1467a27db2673ba` |
| Android x64 | API 24 | `536827216b70de5275b35aa087b329b60e711d4d51a52508a83b0b7d803382d0` |
| iOS arm64 device | iOS 13 | `044cbaf42f8c08ad061276dbe8e72de43f4e8d628f0a15399d236cb8abc8dccb` |
| iOS arm64 simulator | iOS 14 | `1732da73449c700fed8cbbcecb4fc2244f8f33921b65c550233592ed56218da1` |
| iOS x64 simulator | iOS 13 | `831a5cc8446e1e5a8d676fb5a91ed0738cf6a265a197ab9b78f2f083b2a72dd5` |
| Linux arm64 | glibc 2.31 | `efd0b7e5c2931b8572ac774e7b0f29673d36e20f3b2c05385ddd19aa49edfb14` |
| Linux x64 | glibc 2.31 | `041f381e57f624177ba59fa3d60f4ff4fdda5ba4dbee81040992b0bb956fb655` |
| macOS arm64 | macOS 12 | `db00e5fb482091c71126ca767582f5baee6fa4c59bcbbbf4581d6136e4034f9d` |
| macOS x64 | macOS 12 | `534b985a1c26db85d8d66de0cf990d56c15e05de2235a61ee67635120e605151` |
| Windows x64 | Windows 10 | `082e4da5f20c4d161f88a4c8c4a152124b55a8447c632b11008cb067713e6e5f` |
| Browser Wasm | Emscripten 5.0.0 | `1cf5e9ec3c3465f924c42eaa5083ff9cda3168a83ff55951c641db392e368a5c` |

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
dart run tool/verify_artifacts.dart
```

Because FFmpeg is statically included inside the final shim library, downstream
binary distributors must review LGPL requirements. The corresponding source
revisions and complete relink scripts are recorded above; retain them with any
distributed binary.
