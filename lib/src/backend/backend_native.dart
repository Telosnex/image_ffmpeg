import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../image_ffmpeg_bindings_generated.dart' as native;
import '../models.dart';
import 'backend.dart';

Future<FfmpegBackend> loadBackend() async {
  final abiVersion = native.image_ffmpeg_abi_version();
  if (abiVersion != native.IMAGE_FFMPEG_ABI_VERSION) {
    throw StateError(
      'image_ffmpeg ABI mismatch: Dart expects '
      '${native.IMAGE_FFMPEG_ABI_VERSION}, native asset provides $abiVersion',
    );
  }

  final buildInfo = native
      .image_ffmpeg_build_info()
      .cast<Utf8>()
      .toDartString();
  return _NativeBackend(
    FfmpegCapabilities(
      runtime: FfmpegRuntime.native,
      abiVersion: abiVersion,
      buildInfo: buildInfo,
      canDecodeImage: native.image_ffmpeg_has_ffmpeg() != 0,
    ),
  );
}

final class _NativeBackend implements FfmpegBackend {
  const _NativeBackend(this.capabilities);

  @override
  final FfmpegCapabilities capabilities;

  @override
  Future<ImageInfo> probeImage(Uint8List encoded) =>
      Isolate.run(() => _probeImageOnHelperIsolate(encoded));

  @override
  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  }) => Isolate.run(
    () => _decodeImageOnHelperIsolate(encoded, maxWidth, maxHeight),
  );

  @override
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  }) => Isolate.run(
    () => _encodeOnHelperIsolate(
      image,
      quality,
      _EncodedFormat.jpeg,
      chroma: chroma,
      backgroundColor: backgroundColor,
    ),
  );

  @override
  Future<Uint8List> encodePng(
    RgbaImage image, {
    required int compressionLevel,
  }) => Isolate.run(
    () => _encodeOnHelperIsolate(image, compressionLevel, _EncodedFormat.png),
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
  }) => Isolate.run(
    () => _transcodeOnHelperIsolate(
      encoded,
      output,
      maxWidth,
      maxHeight,
      applyOrientation,
      crop,
      passthroughIfUnchanged,
    ),
  );

  @override
  Future<void> dispose() async {}
}

enum _EncodedFormat { jpeg, png }

Uint8List _encodeOnHelperIsolate(
  RgbaImage image,
  int option,
  _EncodedFormat format, {
  JpegChroma chroma = JpegChroma.yuv420,
  int backgroundColor = 0xffffffff,
}) {
  final input = calloc<Uint8>(image.bytes.length);
  final output = calloc<native.image_ffmpeg_buffer>();
  try {
    input.asTypedList(image.bytes.length).setAll(0, image.bytes);
    final status = switch (format) {
      _EncodedFormat.jpeg => native.image_ffmpeg_encode_jpeg_rgba_ex(
        input,
        image.bytes.length,
        image.width,
        image.height,
        image.stride,
        option,
        chroma.index,
        backgroundColor,
        output,
      ),
      _EncodedFormat.png => native.image_ffmpeg_encode_png_rgba(
        input,
        image.bytes.length,
        image.width,
        image.height,
        image.stride,
        option,
        output,
      ),
    };
    if (status != 0) {
      final message = native
          .image_ffmpeg_error_message(status)
          .cast<Utf8>()
          .toDartString();
      throw FfmpegException(status, message);
    }
    return Uint8List.fromList(output.ref.data.asTypedList(output.ref.length));
  } finally {
    native.image_ffmpeg_buffer_release(output);
    calloc.free(output);
    calloc.free(input);
  }
}

ImageInfo _probeImageOnHelperIsolate(Uint8List encoded) {
  final input = calloc<Uint8>(encoded.length);
  final output = calloc<native.image_ffmpeg_image_info>();
  try {
    input.asTypedList(encoded.length).setAll(0, encoded);
    final status = native.image_ffmpeg_probe_image(
      input,
      encoded.length,
      output,
    );
    _throwForStatus(status);
    final info = output.ref;
    return ImageInfo(
      format: ImageFormat.values[info.format],
      width: info.width,
      height: info.height,
      displayWidth: info.display_width,
      displayHeight: info.display_height,
      orientation: ImageOrientation.values[info.orientation - 1],
      frameCount: info.frame_count,
      hasAlpha: switch (info.has_alpha) {
        0 => false,
        1 => true,
        _ => null,
      },
    );
  } finally {
    calloc.free(output);
    calloc.free(input);
  }
}

EncodedImage _transcodeOnHelperIsolate(
  Uint8List encoded,
  ImageOutput outputSettings,
  int maxWidth,
  int maxHeight,
  bool applyOrientation,
  ImageCrop? crop,
  bool passthroughIfUnchanged,
) {
  final input = calloc<Uint8>(encoded.length);
  final options = calloc<native.image_ffmpeg_transcode_options>();
  final output = calloc<native.image_ffmpeg_encoded_image>();
  try {
    input.asTypedList(encoded.length).setAll(0, encoded);
    final settings = options.ref;
    settings
      ..output_format = outputSettings.format.index
      ..max_width = maxWidth
      ..max_height = maxHeight
      ..apply_orientation = applyOrientation ? 1 : 0
      ..crop_x = crop?.x ?? 0
      ..crop_y = crop?.y ?? 0
      ..crop_width = crop?.width ?? 0
      ..crop_height = crop?.height ?? 0
      ..jpeg_quality = 80
      ..jpeg_chroma = JpegChroma.yuv420.index
      ..jpeg_background_argb = 0xffffffff
      ..png_compression_level = 6
      ..passthrough_if_unchanged = passthroughIfUnchanged ? 1 : 0;
    switch (outputSettings) {
      case JpegImageOutput():
        settings
          ..jpeg_quality = outputSettings.quality
          ..jpeg_chroma = outputSettings.chroma.index
          ..jpeg_background_argb = outputSettings.backgroundColor;
      case PngImageOutput():
        settings.png_compression_level = outputSettings.compressionLevel;
    }
    final status = native.image_ffmpeg_transcode_image(
      input,
      encoded.length,
      options,
      output,
    );
    _throwForStatus(status);
    final result = output.ref;
    return EncodedImage(
      bytes: Uint8List.fromList(result.data.asTypedList(result.length)),
      width: result.width,
      height: result.height,
      format: ImageFormat.values[result.format],
    );
  } finally {
    native.image_ffmpeg_encoded_image_release(output);
    calloc.free(output);
    calloc.free(options);
    calloc.free(input);
  }
}

void _throwForStatus(int status) {
  if (status == 0) return;
  final message = native
      .image_ffmpeg_error_message(status)
      .cast<Utf8>()
      .toDartString();
  throw FfmpegException(status, message);
}

RgbaImage _decodeImageOnHelperIsolate(
  Uint8List encoded,
  int maxWidth,
  int maxHeight,
) {
  final input = calloc<Uint8>(encoded.length);
  final output = calloc<native.image_ffmpeg_image>();
  try {
    input.asTypedList(encoded.length).setAll(0, encoded);
    final status = native.image_ffmpeg_decode_image_rgba(
      input,
      encoded.length,
      maxWidth,
      maxHeight,
      output,
    );
    if (status != 0) {
      final message = native
          .image_ffmpeg_error_message(status)
          .cast<Utf8>()
          .toDartString();
      throw FfmpegException(status, message);
    }

    final image = output.ref;
    if (image.pixel_format !=
        native
            .image_ffmpeg_pixel_format
            .IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888
            .value) {
      throw FfmpegException(
        -5,
        'Native asset returned unsupported pixel format ${image.pixel_format}',
      );
    }
    return RgbaImage(
      width: image.width,
      height: image.height,
      stride: image.stride,
      // Copy before releasing memory owned by the C shim. A future zero-copy
      // API can wrap malloc memory with NativeFinalizer, but this safe path is
      // also the same ownership shape as copying from Wasm linear memory.
      bytes: Uint8List.fromList(image.data.asTypedList(image.length)),
    );
  } finally {
    native.image_ffmpeg_image_release(output);
    calloc.free(output);
    calloc.free(input);
  }
}
