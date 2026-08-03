import 'dart:typed_data';

import 'backend/backend.dart';
import 'backend/backend_stub.dart'
    if (dart.library.ffi) 'backend/backend_native.dart'
    if (dart.library.js_interop) 'backend/backend_web.dart'
    as platform;
import 'models.dart';

/// Cross-platform entry point for the reduced FFmpeg build.
///
/// The API is asynchronous on every platform. Native decoding runs on a helper
/// isolate; browser decoding will run in a Web Worker. Keeping that distinction
/// below this class avoids platform-specific call sites.
final class Ffmpeg {
  Ffmpeg._(this._backend);

  final FfmpegBackend _backend;
  bool _disposed = false;

  /// Loads and validates the native code asset or browser Wasm module.
  static Future<Ffmpeg> load() async => Ffmpeg._(await platform.loadBackend());

  FfmpegCapabilities get capabilities => _backend.capabilities;

  /// Reads format, geometry, orientation, frame-count, and alpha metadata
  /// without allocating a decoded pixel buffer.
  Future<ImageInfo> probeImage(Uint8List bytes) {
    _validateEncodedBytes(bytes);
    return _backend.probeImage(bytes);
  }

  /// Probes and decodes arbitrary encoded image [bytes] to RGBA8888.
  ///
  /// The first frame is returned for animated images. Passing zero for either
  /// maximum leaves that axis unconstrained; zero for both preserves the source
  /// dimensions. Images are never upscaled.
  ///
  /// Throws [FfmpegException] when the bytes are not a recognized image, the
  /// build does not include its decoder, or decoding fails.
  Future<RgbaImage> decodeImage(
    Uint8List bytes, {
    int maxWidth = 0,
    int maxHeight = 0,
  }) {
    _validateEncodedBytes(bytes);
    if (maxWidth < 0) throw ArgumentError.value(maxWidth, 'maxWidth');
    if (maxHeight < 0) throw ArgumentError.value(maxHeight, 'maxHeight');
    _validateUint32(maxWidth, 'maxWidth');
    _validateUint32(maxHeight, 'maxHeight');
    return _backend.decodeImage(
      bytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Encodes RGBA8888 pixels as JPEG.
  ///
  /// [quality] ranges from 1 (lowest) to 100 (highest). JPEG cannot represent
  /// alpha, so pixels are composited onto [backgroundColor] before encoding.
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    int quality = 80,
    JpegChroma chroma = JpegChroma.yuv420,
    int backgroundColor = 0xffffffff,
  }) {
    _validateEncodeImage(image);
    _validateJpegOptions(quality, backgroundColor);
    return _backend.encodeJpeg(
      image,
      quality: quality,
      chroma: chroma,
      backgroundColor: backgroundColor,
    );
  }

  /// Encodes RGBA8888 pixels as PNG while preserving alpha.
  ///
  /// [compressionLevel] ranges from 0 (fastest) to 9 (smallest).
  Future<Uint8List> encodePng(RgbaImage image, {int compressionLevel = 6}) {
    _validateEncodeImage(image);
    _validatePngCompression(compressionLevel);
    return _backend.encodePng(image, compressionLevel: compressionLevel);
  }

  /// Decodes the first frame, optionally applies EXIF orientation, crops in
  /// post-orientation coordinates, performs fit-within scaling, and encodes—all
  /// within one native/Wasm call so RGBA pixels do not cross into Dart.
  Future<EncodedImage> transcodeImage(
    Uint8List bytes, {
    required ImageOutput output,
    int maxWidth = 0,
    int maxHeight = 0,
    bool applyOrientation = true,
    ImageCrop? crop,
    bool passthroughIfUnchanged = false,
  }) {
    _validateEncodedBytes(bytes);
    if (maxWidth < 0) throw ArgumentError.value(maxWidth, 'maxWidth');
    if (maxHeight < 0) throw ArgumentError.value(maxHeight, 'maxHeight');
    _validateUint32(maxWidth, 'maxWidth');
    _validateUint32(maxHeight, 'maxHeight');
    if (crop != null) {
      if (crop.x < 0 || crop.y < 0 || crop.width <= 0 || crop.height <= 0) {
        throw ArgumentError.value(crop, 'crop', 'must have positive geometry');
      }
      _validateUint32(crop.x, 'crop.x');
      _validateUint32(crop.y, 'crop.y');
      _validateUint32(crop.width, 'crop.width');
      _validateUint32(crop.height, 'crop.height');
    }
    switch (output) {
      case JpegImageOutput():
        _validateJpegOptions(output.quality, output.backgroundColor);
      case PngImageOutput():
        _validatePngCompression(output.compressionLevel);
    }
    return _backend.transcodeImage(
      bytes,
      output: output,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      applyOrientation: applyOrientation,
      crop: crop,
      passthroughIfUnchanged: passthroughIfUnchanged,
    );
  }

  void _validateEncodedBytes(Uint8List bytes) {
    if (_disposed) throw StateError('Ffmpeg has been disposed');
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes');
    _validateUint32(bytes.length, 'bytes.length');
  }

  void _validateJpegOptions(int quality, int backgroundColor) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be from 1 to 100');
    }
    _validateUint32(backgroundColor, 'backgroundColor');
  }

  void _validatePngCompression(int compressionLevel) {
    if (compressionLevel < 0 || compressionLevel > 9) {
      throw ArgumentError.value(
        compressionLevel,
        'compressionLevel',
        'must be from 0 to 9',
      );
    }
  }

  void _validateUint32(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, name, 'must fit uint32');
    }
  }

  void _validateEncodeImage(RgbaImage image) {
    if (_disposed) throw StateError('Ffmpeg has been disposed');
    if (image.width > 0xffffffff ||
        image.height > 0xffffffff ||
        image.stride > 0xffffffff ||
        image.bytes.length > 0xffffffff) {
      throw ArgumentError.value(image, 'image', 'geometry exceeds uint32');
    }
  }

  /// Compatibility alias for the original JPEG-only API.
  @Deprecated('Use decodeImage')
  Future<RgbaImage> decodeJpeg(
    Uint8List encoded, {
    int maxWidth = 0,
    int maxHeight = 0,
  }) => decodeImage(encoded, maxWidth: maxWidth, maxHeight: maxHeight);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _backend.dispose();
  }
}
