import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:image_ffmpeg/image_ffmpeg.dart';

const syntheticOperationCorpusVersion = 1;

const syntheticOperationIds = <String>[
  'v1/decode-prime-17x13',
  'v1/decode-prime-19x11',
  'v1/decode-prime-23x17',
  'v1/encode-padding-7',
  'v1/encode-padding-13',
  'v1/encode-padding-29',
  'v1/crop-top-left',
  'v1/crop-bottom-right',
  'v1/crop-one-pixel',
  'v1/crop-prime-interior',
  'v1/fill-top-edge',
  'v1/fill-bottom-right',
  'v1/fill-one-pixel',
  'v1/fill-transparent-hidden-rgb',
  'v1/box-include-landscape',
  'v1/box-include-portrait',
  'v1/box-opaque-landscape',
  'v1/box-opaque-portrait',
  'v1/passthrough-png',
  'v1/crop-fit-prime-rounding',
  'v1/jpeg-transparent-background',
];

final class SyntheticSource {
  const SyntheticSource({
    required this.width,
    required this.height,
    required this.rgba,
    required this.png,
  });

  final int width;
  final int height;
  final Uint8List rgba;
  final Uint8List png;
}

SyntheticSource buildSyntheticSource({
  required int width,
  required int height,
  required int seed,
}) {
  final rgba = Uint8List(width * height * 4);
  var state = seed & 0xffffffff;
  int next() {
    state ^= (state << 13) & 0xffffffff;
    state ^= state >>> 17;
    state ^= (state << 5) & 0xffffffff;
    return state & 0xffffffff;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final random = next();
      final alpha = switch ((x * 3 + y * 5 + seed) % 7) {
        0 => 0,
        1 => 63,
        2 => 127,
        _ => 255,
      };
      // Alpha-zero pixels deliberately retain nonzero hidden RGB.
      rgba[offset] = (x * 37 + y * 11 + random) & 0xff;
      rgba[offset + 1] = (x * 7 + y * 41 + (random >>> 8)) & 0xff;
      rgba[offset + 2] = (x * 19 + y * 23 + (random >>> 16)) & 0xff;
      rgba[offset + 3] = alpha;
    }
  }
  final independent = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  return SyntheticSource(
    width: width,
    height: height,
    rgba: rgba,
    png: Uint8List.fromList(image.encodePng(independent, level: 6)),
  );
}

RgbaImage paddedRgba(SyntheticSource source, int padding) {
  final stride = source.width * 4 + padding;
  final bytes = Uint8List(stride * source.height)
    ..fillRange(0, stride * source.height, 0xa5);
  for (var y = 0; y < source.height; y++) {
    bytes.setRange(
      y * stride,
      y * stride + source.width * 4,
      source.rgba,
      y * source.width * 4,
    );
  }
  return RgbaImage(
    width: source.width,
    height: source.height,
    stride: stride,
    bytes: bytes,
  );
}

Uint8List cropRgba(SyntheticSource source, ImageCrop crop) {
  final output = Uint8List(crop.width * crop.height * 4);
  for (var y = 0; y < crop.height; y++) {
    final sourceOffset = ((crop.y + y) * source.width + crop.x) * 4;
    output.setRange(
      y * crop.width * 4,
      (y + 1) * crop.width * 4,
      source.rgba,
      sourceOffset,
    );
  }
  return output;
}

Uint8List fillRgba(SyntheticSource source, ImageFillRect fill) {
  final output = Uint8List.fromList(source.rgba);
  final red = (fill.color >>> 16) & 0xff;
  final green = (fill.color >>> 8) & 0xff;
  final blue = fill.color & 0xff;
  final alpha = (fill.color >>> 24) & 0xff;
  for (var y = fill.y; y < fill.y + fill.height; y++) {
    for (var x = fill.x; x < fill.x + fill.width; x++) {
      final offset = (y * source.width + x) * 4;
      output[offset] = red;
      output[offset + 1] = green;
      output[offset + 2] = blue;
      output[offset + 3] = alpha;
    }
  }
  return output;
}

RgbaImage boxAverage(
  SyntheticSource source,
  int maxDimension,
  BoxAverageAlphaMode alphaMode,
) {
  var width = source.width;
  var height = source.height;
  if (width > maxDimension || height > maxDimension) {
    if (width >= height) {
      height = math.max(1, source.height * maxDimension ~/ source.width);
      width = maxDimension;
    } else {
      width = math.max(1, source.width * maxDimension ~/ source.height);
      height = maxDimension;
    }
  }
  final output = Uint8List(width * height * 4);
  for (var destinationY = 0; destinationY < height; destinationY++) {
    final startY = (destinationY * source.height + height - 1) ~/ height;
    final endY = ((destinationY + 1) * source.height + height - 1) ~/ height;
    for (var destinationX = 0; destinationX < width; destinationX++) {
      final startX = (destinationX * source.width + width - 1) ~/ width;
      final endX = ((destinationX + 1) * source.width + width - 1) ~/ width;
      var red = 0;
      var green = 0;
      var blue = 0;
      var alpha = 0;
      var count = 0;
      for (var sourceY = startY; sourceY < endY; sourceY++) {
        for (var sourceX = startX; sourceX < endX; sourceX++) {
          final offset = (sourceY * source.width + sourceX) * 4;
          if (alphaMode == BoxAverageAlphaMode.opaqueOnly &&
              source.rgba[offset + 3] != 255) {
            continue;
          }
          red += source.rgba[offset];
          green += source.rgba[offset + 1];
          blue += source.rgba[offset + 2];
          alpha += source.rgba[offset + 3];
          count++;
        }
      }
      if (count == 0) continue;
      final offset = (destinationY * width + destinationX) * 4;
      final half = count >> 1;
      output[offset] = (red + half) ~/ count;
      output[offset + 1] = (green + half) ~/ count;
      output[offset + 2] = (blue + half) ~/ count;
      output[offset + 3] = alphaMode == BoxAverageAlphaMode.opaqueOnly
          ? 255
          : (alpha + half) ~/ count;
    }
  }
  return RgbaImage(
    width: width,
    height: height,
    stride: width * 4,
    bytes: output,
  );
}
