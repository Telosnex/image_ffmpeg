import 'dart:typed_data';

import '../models.dart';

/// Internal contract implemented by native FFI and browser Wasm adapters.
abstract interface class FfmpegBackend {
  FfmpegCapabilities get capabilities;

  Future<ImageInfo> probeImage(Uint8List encoded);

  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  });

  Future<RgbaImage> decodeImageBoxAverage(
    Uint8List encoded, {
    required int maxDimension,
    required BoxAverageAlphaMode alphaMode,
  });

  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  });

  Future<Uint8List> encodePng(RgbaImage image, {required int compressionLevel});

  Future<EncodedImage> transcodeImage(
    Uint8List encoded, {
    required ImageOutput output,
    required int maxWidth,
    required int maxHeight,
    required bool applyOrientation,
    required ImageCrop? crop,
    required ImageFillRect? fill,
    required bool passthroughIfUnchanged,
  });
}
