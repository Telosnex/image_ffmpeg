import 'dart:typed_data';

/// Execution engine behind [Ffmpeg].
enum FfmpegRuntime {
  /// A code asset called through `dart:ffi`.
  native,

  /// A separately instantiated linear-memory Wasm module.
  webAssembly,

  /// No supported backend exists on this platform.
  unsupported,
}

/// Runtime information discovered while loading the package.
final class FfmpegCapabilities {
  const FfmpegCapabilities({
    required this.runtime,
    required this.abiVersion,
    required this.buildInfo,
    required this.canDecodeImage,
  });

  final FfmpegRuntime runtime;
  final int abiVersion;
  final String buildInfo;

  /// Whether this build can probe and decode encoded image bytes.
  final bool canDecodeImage;

  /// Whether this build can encode RGBA8888 pixels as JPEG.
  bool get canEncodeJpeg => canDecodeImage;

  /// Whether this build can encode RGBA8888 pixels as PNG.
  bool get canEncodePng => canDecodeImage;

  /// Compatibility alias for callers written against the JPEG-only scaffold.
  @Deprecated('Use canDecodeImage')
  bool get canDecodeJpeg => canDecodeImage;

  @override
  String toString() =>
      'FfmpegCapabilities(runtime: $runtime, abiVersion: $abiVersion, '
      'canDecodeImage: $canDecodeImage, canEncodeJpeg: $canEncodeJpeg, '
      'canEncodePng: $canEncodePng, buildInfo: $buildInfo)';
}

/// Encoded image formats recognized by the reduced build.
enum ImageFormat {
  unknown,
  jpeg,
  png,
  apng,
  webp,
  gif,
  bmp,
  tiff,
  avif,
  psd,
  ico,
}

/// The transform described by the EXIF Orientation tag.
enum ImageOrientation {
  normal,
  flipHorizontal,
  rotate180,
  flipVertical,
  transpose,
  rotate90,
  transverse,
  rotate270,
}

/// JPEG chroma resolution.
enum JpegChroma {
  /// One chroma pair per 2×2 luma block; compact and well suited to photos.
  yuv420,

  /// Full chroma at every pixel; preferred for screenshots and colored text.
  yuv444,
}

/// Image metadata obtained without materializing decoded pixels.
final class ImageInfo {
  const ImageInfo({
    required this.format,
    required this.width,
    required this.height,
    required this.displayWidth,
    required this.displayHeight,
    required this.orientation,
    required this.frameCount,
    required this.hasAlpha,
  });

  final ImageFormat format;

  /// Coded dimensions before applying [orientation].
  final int width;
  final int height;

  /// Dimensions after applying [orientation].
  final int displayWidth;
  final int displayHeight;

  final ImageOrientation orientation;

  /// Advertised frame count, or zero when the container does not provide one.
  final int frameCount;

  /// Whether alpha is present, or `null` when probing cannot determine it.
  final bool? hasAlpha;
}

/// A crop rectangle applied before fit-within scaling.
final class ImageCrop {
  const ImageCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) : assert(x >= 0),
       assert(y >= 0),
       assert(width > 0),
       assert(height > 0);

  final int x;
  final int y;
  final int width;
  final int height;
}

/// Output settings for [Ffmpeg.transcodeImage].
sealed class ImageOutput {
  const ImageOutput();

  const factory ImageOutput.jpeg({
    int quality,
    JpegChroma chroma,
    int backgroundColor,
  }) = JpegImageOutput;

  const factory ImageOutput.png({int compressionLevel}) = PngImageOutput;

  ImageFormat get format;
}

final class JpegImageOutput extends ImageOutput {
  const JpegImageOutput({
    this.quality = 80,
    this.chroma = JpegChroma.yuv420,
    this.backgroundColor = 0xffffffff,
  });

  final int quality;
  final JpegChroma chroma;

  /// Alpha-compositing background as `0xAARRGGBB`; its alpha byte is ignored.
  final int backgroundColor;

  @override
  ImageFormat get format => ImageFormat.jpeg;
}

final class PngImageOutput extends ImageOutput {
  const PngImageOutput({this.compressionLevel = 6});

  final int compressionLevel;

  @override
  ImageFormat get format => ImageFormat.png;
}

/// Encoded output and its post-transform dimensions.
final class EncodedImage {
  const EncodedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final ImageFormat format;
}

/// Tightly packed RGBA8888 output.
final class RgbaImage {
  RgbaImage({
    required this.width,
    required this.height,
    required this.stride,
    required this.bytes,
  }) {
    if (width <= 0 || height <= 0 || stride < width * 4) {
      throw ArgumentError('Invalid RGBA image geometry');
    }
    if (bytes.length < stride * height) {
      throw ArgumentError('RGBA buffer is smaller than its geometry');
    }
  }

  final int width;
  final int height;
  final int stride;
  final Uint8List bytes;
}

/// An error returned by the portable C ABI or Wasm equivalent.
final class FfmpegException implements Exception {
  const FfmpegException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'FfmpegException($status): $message';
}
