import 'dart:typed_data';

import '../models.dart';
import 'backend.dart';

/// Browser adapter seam.
///
/// The public API already selects this implementation for both JavaScript and
/// WasmGC Flutter web builds. The next integration step is to instantiate
/// `web/image_ffmpeg.mjs` in a Worker and implement the two message types in
/// that file. Keeping the placeholder here lets native and web call sites be
/// written and analyzed now without pretending `dart:ffi` works in a browser.
Future<FfmpegBackend> loadBackend() async => const _WebBackend();

final class _WebBackend implements FfmpegBackend {
  const _WebBackend();

  @override
  FfmpegCapabilities get capabilities => const FfmpegCapabilities(
    runtime: FfmpegRuntime.webAssembly,
    abiVersion: 2,
    buildInfo: 'WebAssembly adapter scaffold (module not built)',
    canDecodeImage: false,
  );

  @override
  Future<ImageInfo> probeImage(Uint8List encoded) =>
      throw const FfmpegException(
        -2,
        'FFmpeg WebAssembly module has not been built and bundled',
      );

  @override
  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  }) => throw const FfmpegException(
    -2,
    'FFmpeg WebAssembly module has not been built and bundled',
  );

  @override
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  }) => throw const FfmpegException(
    -2,
    'FFmpeg WebAssembly module has not been built and bundled',
  );

  @override
  Future<Uint8List> encodePng(
    RgbaImage image, {
    required int compressionLevel,
  }) => throw const FfmpegException(
    -2,
    'FFmpeg WebAssembly module has not been built and bundled',
  );

  @override
  Future<EncodedImage> transcodeImage(
    Uint8List encoded, {
    required ImageOutput output,
    required int maxWidth,
    required int maxHeight,
    required bool applyOrientation,
    required ImageCrop? crop,
    required bool passthroughIfUnchanged,
  }) => throw const FfmpegException(
    -2,
    'FFmpeg WebAssembly module has not been built and bundled',
  );

  @override
  Future<void> dispose() async {}
}
