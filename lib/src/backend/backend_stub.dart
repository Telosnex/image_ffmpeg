import 'dart:typed_data';

import '../models.dart';
import 'backend.dart';

Future<FfmpegBackend> loadBackend() async => const _UnsupportedBackend();

final class _UnsupportedBackend implements FfmpegBackend {
  const _UnsupportedBackend();

  @override
  FfmpegCapabilities get capabilities => const FfmpegCapabilities(
    runtime: FfmpegRuntime.unsupported,
    abiVersion: 0,
    buildInfo: 'No image_ffmpeg backend for this platform',
    canDecodeImage: false,
  );

  @override
  Future<ImageInfo> probeImage(Uint8List encoded) =>
      throw const FfmpegException(-5, 'Unsupported platform');

  @override
  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  }) => throw const FfmpegException(-5, 'Unsupported platform');

  @override
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  }) => throw const FfmpegException(-5, 'Unsupported platform');

  @override
  Future<Uint8List> encodePng(
    RgbaImage image, {
    required int compressionLevel,
  }) => throw const FfmpegException(-5, 'Unsupported platform');

  @override
  Future<EncodedImage> transcodeImage(
    Uint8List encoded, {
    required ImageOutput output,
    required int maxWidth,
    required int maxHeight,
    required bool applyOrientation,
    required ImageCrop? crop,
    required bool passthroughIfUnchanged,
  }) => throw const FfmpegException(-5, 'Unsupported platform');

  @override
  Future<void> dispose() async {}
}
