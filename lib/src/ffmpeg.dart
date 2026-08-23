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
/// isolate; browser decoding runs in a Web Worker. Keeping that distinction
/// below this class avoids platform-specific call sites. Initialization is
/// lazy and shared; callers do not acquire or dispose a codec handle.
abstract final class ImageFfmpeg {
  static Future<FfmpegBackend>? _backend;

  static Future<FfmpegBackend> _getBackend() => _backend ??= _loadBackend();

  static Future<FfmpegBackend> _loadBackend() async {
    try {
      return await platform.loadBackend();
    } on Object {
      // A failed browser Worker URL or ABI check must not poison future loads.
      _backend = null;
      rethrow;
    }
  }

  /// Loads the shared backend if necessary and reports its capabilities.
  static Future<FfmpegCapabilities> get capabilities async =>
      (await _getBackend()).capabilities;

  /// Reads format, geometry, orientation, frame-count, and alpha metadata
  /// without allocating a decoded pixel buffer.
  static Future<ImageInfo> probeImage(Uint8List bytes) async {
    _validateEncodedBytes(bytes);
    final snapshot = platform.snapshotBytes(bytes);
    return (await _getBackend()).probeImage(snapshot);
  }

  /// Probes and decodes arbitrary encoded image [bytes] to RGBA8888.
  ///
  /// The first frame is returned for animated images. Passing zero for either
  /// maximum leaves that axis unconstrained; zero for both preserves the source
  /// dimensions. Images are never upscaled.
  ///
  /// Throws [FfmpegException] when the bytes are not a recognized image, the
  /// build does not include its decoder, or decoding fails.
  static Future<RgbaImage> decodeImage(
    Uint8List bytes, {
    int maxWidth = 0,
    int maxHeight = 0,
  }) async {
    _validateEncodedBytes(bytes);
    if (maxWidth < 0) throw ArgumentError.value(maxWidth, 'maxWidth');
    if (maxHeight < 0) throw ArgumentError.value(maxHeight, 'maxHeight');
    _validateUint32(maxWidth, 'maxWidth');
    _validateUint32(maxHeight, 'maxHeight');
    final snapshot = platform.snapshotBytes(bytes);
    return (await _getBackend()).decodeImage(
      snapshot,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  /// Decodes at full resolution, then performs deterministic integer-only box
  /// averaging while the full RGBA buffer remains in native/Wasm memory.
  ///
  /// Every source pixel belongs to exactly one destination cell. The result
  /// fits inside a [maxDimension] square without upscaling. Unlike
  /// [decodeImage]'s FFmpeg scaler, this operation has fixed cell boundaries
  /// and rounding semantics intended for stable color extraction.
  static Future<RgbaImage> decodeImageBoxAverage(
    Uint8List bytes, {
    required int maxDimension,
    BoxAverageAlphaMode alphaMode = BoxAverageAlphaMode.include,
  }) async {
    _validateEncodedBytes(bytes);
    if (maxDimension <= 0) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'must be positive',
      );
    }
    _validateUint32(maxDimension, 'maxDimension');
    final snapshot = platform.snapshotBytes(bytes);
    return (await _getBackend()).decodeImageBoxAverage(
      snapshot,
      maxDimension: maxDimension,
      alphaMode: alphaMode,
    );
  }

  /// Encodes RGBA8888 pixels as JPEG.
  ///
  /// [quality] ranges from 1 (lowest) to 100 (highest). JPEG cannot represent
  /// alpha, so pixels are composited onto [backgroundColor] before encoding.
  static Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    int quality = 80,
    JpegChroma chroma = JpegChroma.yuv420,
    int backgroundColor = 0xffffffff,
  }) async {
    _validateEncodeImage(image);
    _validateJpegOptions(quality, backgroundColor);
    final snapshot = _snapshotImage(image);
    return (await _getBackend()).encodeJpeg(
      snapshot,
      quality: quality,
      chroma: chroma,
      backgroundColor: backgroundColor,
    );
  }

  /// Encodes RGBA8888 pixels as PNG while preserving alpha.
  ///
  /// [compressionLevel] ranges from 0 (fastest) to 9 (smallest).
  static Future<Uint8List> encodePng(
    RgbaImage image, {
    int compressionLevel = 6,
  }) async {
    _validateEncodeImage(image);
    _validatePngCompression(compressionLevel);
    final snapshot = _snapshotImage(image);
    return (await _getBackend()).encodePng(
      snapshot,
      compressionLevel: compressionLevel,
    );
  }

  /// Decodes the first frame, optionally applies EXIF orientation, crops in
  /// post-orientation coordinates, performs fit-within scaling, and encodes—all
  /// within one native/Wasm call so RGBA pixels do not cross into Dart.
  static Future<EncodedImage> transcodeImage(
    Uint8List bytes, {
    required ImageOutput output,
    int maxWidth = 0,
    int maxHeight = 0,
    bool applyOrientation = true,
    ImageCrop? crop,
    bool passthroughIfUnchanged = false,
  }) async {
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
    _validateOutput(output);
    final snapshot = platform.snapshotBytes(bytes);
    return (await _getBackend()).transcodeImage(
      snapshot,
      output: output,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      applyOrientation: applyOrientation,
      crop: crop,
      fill: null,
      passthroughIfUnchanged: passthroughIfUnchanged,
    );
  }

  /// Decodes, fills one solid rectangle, and encodes in one native/Wasm call.
  ///
  /// The full-resolution RGBA intermediate never crosses into Dart. The fill
  /// is applied after optional orientation and before encoding, making this
  /// suitable for high-frequency screenshot redaction and masking.
  static Future<EncodedImage> fillRectangle(
    Uint8List bytes, {
    required ImageFillRect rectangle,
    required ImageOutput output,
    bool applyOrientation = false,
  }) async {
    _validateEncodedBytes(bytes);
    _validateFillRect(rectangle);
    _validateOutput(output);
    final snapshot = platform.snapshotBytes(bytes);
    return (await _getBackend()).transcodeImage(
      snapshot,
      output: output,
      maxWidth: 0,
      maxHeight: 0,
      applyOrientation: applyOrientation,
      crop: null,
      fill: rectangle,
      passthroughIfUnchanged: false,
    );
  }

  static void _validateEncodedBytes(Uint8List bytes) {
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes');
    _validateUint32(bytes.length, 'bytes.length');
  }

  static RgbaImage _snapshotImage(RgbaImage image) {
    final bytes = platform.snapshotBytes(image.bytes);
    if (identical(bytes, image.bytes)) return image;
    return RgbaImage(
      width: image.width,
      height: image.height,
      stride: image.stride,
      bytes: bytes,
    );
  }

  static void _validateJpegOptions(int quality, int backgroundColor) {
    if (quality < 1 || quality > 100) {
      throw ArgumentError.value(quality, 'quality', 'must be from 1 to 100');
    }
    _validateUint32(backgroundColor, 'backgroundColor');
  }

  static void _validateFillRect(ImageFillRect rectangle) {
    if (rectangle.x < 0 ||
        rectangle.y < 0 ||
        rectangle.width <= 0 ||
        rectangle.height <= 0) {
      throw ArgumentError.value(
        rectangle,
        'rectangle',
        'must have positive geometry',
      );
    }
    _validateUint32(rectangle.x, 'rectangle.x');
    _validateUint32(rectangle.y, 'rectangle.y');
    _validateUint32(rectangle.width, 'rectangle.width');
    _validateUint32(rectangle.height, 'rectangle.height');
    _validateUint32(rectangle.color, 'rectangle.color');
  }

  static void _validateOutput(ImageOutput output) {
    switch (output) {
      case JpegImageOutput():
        _validateJpegOptions(output.quality, output.backgroundColor);
      case PngImageOutput():
        _validatePngCompression(output.compressionLevel);
    }
  }

  static void _validatePngCompression(int compressionLevel) {
    if (compressionLevel < 0 || compressionLevel > 9) {
      throw ArgumentError.value(
        compressionLevel,
        'compressionLevel',
        'must be from 0 to 9',
      );
    }
  }

  static void _validateUint32(int value, String name) {
    if (value < 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, name, 'must fit uint32');
    }
  }

  static void _validateEncodeImage(RgbaImage image) {
    if (image.width > 0xffffffff ||
        image.height > 0xffffffff ||
        image.stride > 0xffffffff ||
        image.bytes.length > 0xffffffff) {
      throw ArgumentError.value(image, 'image', 'geometry exceeds uint32');
    }
  }
}
