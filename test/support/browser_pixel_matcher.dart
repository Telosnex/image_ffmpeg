import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

final class BrowserPixelMetrics {
  const BrowserPixelMetrics({
    required this.maxChannelDelta,
    required this.meanChannelDelta,
    required this.differingPixels,
    required this.pixelCount,
  });

  final int maxChannelDelta;
  final double meanChannelDelta;
  final int differingPixels;
  final int pixelCount;

  @override
  String toString() =>
      'max delta $maxChannelDelta, mean delta '
      '${meanChannelDelta.toStringAsFixed(4)}, differing pixels '
      '$differingPixels/$pixelCount';
}

BrowserPixelMetrics compareRgbaToPng({
  required String caseName,
  required RgbaImage actual,
  required Uint8List pngBytes,
  required int maxChannelDelta,
  required double maxMeanChannelDelta,
}) {
  final decodedReference = image.decodePng(pngBytes);
  if (decodedReference == null) {
    throw StateError('Cannot decode PNG reference for $caseName');
  }
  final expectedImage = decodedReference
      .getFrame(0)
      .convert(format: image.Format.uint8, numChannels: 4);
  expect(
    (actual.width, actual.height),
    (expectedImage.width, expectedImage.height),
    reason: caseName,
  );

  final expected = expectedImage.getBytes(order: image.ChannelOrder.rgba);
  var maximumDelta = 0;
  var totalDelta = 0;
  var differingPixels = 0;
  for (var pixel = 0; pixel < actual.width * actual.height; pixel++) {
    final actualOffset =
        (pixel ~/ actual.width) * actual.stride + (pixel % actual.width) * 4;
    final expectedOffset = pixel * 4;
    final actualAlpha = actual.bytes[actualOffset + 3];
    final expectedAlpha = expected[expectedOffset + 3];
    var pixelDiffers = false;

    for (var channel = 0; channel < 4; channel++) {
      // Ignore invisible RGB differences beneath zero alpha by comparing
      // visible premultiplied colour plus alpha.
      final actualValue = channel == 3
          ? actualAlpha
          : (actual.bytes[actualOffset + channel] * actualAlpha + 127) ~/ 255;
      final expectedValue = channel == 3
          ? expectedAlpha
          : (expected[expectedOffset + channel] * expectedAlpha + 127) ~/ 255;
      final delta = (actualValue - expectedValue).abs();
      maximumDelta = math.max(maximumDelta, delta);
      totalDelta += delta;
      pixelDiffers |= delta != 0;
    }
    if (pixelDiffers) differingPixels++;
  }

  final metrics = BrowserPixelMetrics(
    maxChannelDelta: maximumDelta,
    meanChannelDelta: totalDelta / (actual.width * actual.height * 4),
    differingPixels: differingPixels,
    pixelCount: actual.width * actual.height,
  );
  expect(
    metrics.maxChannelDelta,
    lessThanOrEqualTo(maxChannelDelta),
    reason: '$caseName: $metrics',
  );
  expect(
    metrics.meanChannelDelta,
    lessThanOrEqualTo(maxMeanChannelDelta),
    reason: '$caseName: $metrics',
  );
  return metrics;
}
