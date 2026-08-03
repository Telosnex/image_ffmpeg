import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

const corpusRoot = '../test/fixtures/image_corpus/image';
const corpusFailureRoot = 'test/failures/image_corpus';

List<File> corpusFiles(
  String directory,
  String extension, {
  bool recursive = false,
}) {
  final files =
      Directory('$corpusRoot/$directory')
          .listSync(recursive: recursive)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith(extension))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String corpusRelativePath(File file) =>
    file.path.replaceFirst('$corpusRoot/', '');

void expectValidRgba(RgbaImage decoded, {int? width, int? height}) {
  if (width != null) expect(decoded.width, width);
  if (height != null) expect(decoded.height, height);
  expect(decoded.width, greaterThan(0));
  expect(decoded.height, greaterThan(0));
  expect(decoded.stride, decoded.width * 4);
  expect(decoded.bytes.length, decoded.stride * decoded.height);
}

final class PixelMetrics {
  const PixelMetrics({
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

Future<PixelMetrics> compareRgbaToReference({
  required String caseName,
  required RgbaImage actual,
  required image.Image reference,
  required int maxChannelDelta,
  required double maxMeanChannelDelta,
}) async {
  final expectedImage = reference
      .getFrame(0)
      .convert(format: image.Format.uint8, numChannels: 4);
  expect(
    (actual.width, actual.height),
    (expectedImage.width, expectedImage.height),
    reason: caseName,
  );

  final expected = expectedImage.getBytes(order: image.ChannelOrder.rgba);
  final diff = Uint8List(actual.width * actual.height * 4);
  var maxDelta = 0;
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
      // Ignore invisible RGB differences below zero alpha by comparing visible
      // premultiplied colour plus alpha.
      final actualValue = channel == 3
          ? actualAlpha
          : (actual.bytes[actualOffset + channel] * actualAlpha + 127) ~/ 255;
      final expectedValue = channel == 3
          ? expectedAlpha
          : (expected[expectedOffset + channel] * expectedAlpha + 127) ~/ 255;
      final delta = (actualValue - expectedValue).abs();
      maxDelta = math.max(maxDelta, delta);
      totalDelta += delta;
      pixelDiffers |= delta != 0;
      diff[expectedOffset + channel] = channel == 3
          ? 255
          : math.min(255, delta * 8);
    }
    if (pixelDiffers) differingPixels++;
  }

  final metrics = PixelMetrics(
    maxChannelDelta: maxDelta,
    meanChannelDelta: totalDelta / (actual.width * actual.height * 4),
    differingPixels: differingPixels,
    pixelCount: actual.width * actual.height,
  );

  if (metrics.maxChannelDelta > maxChannelDelta ||
      metrics.meanChannelDelta > maxMeanChannelDelta) {
    await writePixelFailure(
      caseName: caseName,
      actual: actual,
      expected: expectedImage,
      diff: diff,
    );
  }
  expect(
    metrics.maxChannelDelta,
    lessThanOrEqualTo(maxChannelDelta),
    reason: '$caseName: $metrics; inspect $corpusFailureRoot',
  );
  expect(
    metrics.meanChannelDelta,
    lessThanOrEqualTo(maxMeanChannelDelta),
    reason: '$caseName: $metrics; inspect $corpusFailureRoot',
  );
  return metrics;
}

Future<void> writePixelFailure({
  required String caseName,
  required RgbaImage actual,
  required image.Image expected,
  required Uint8List diff,
}) async {
  final directory = Directory(corpusFailureRoot)..createSync(recursive: true);
  final stem = caseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  final actualImage = image.Image.fromBytes(
    width: actual.width,
    height: actual.height,
    bytes: actual.bytes.buffer,
    bytesOffset: actual.bytes.offsetInBytes,
    rowStride: actual.stride,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  final diffImage = image.Image.fromBytes(
    width: actual.width,
    height: actual.height,
    bytes: diff.buffer,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  await File(
    '${directory.path}/${stem}_actual.png',
  ).writeAsBytes(image.encodePng(actualImage));
  await File(
    '${directory.path}/${stem}_expected.png',
  ).writeAsBytes(image.encodePng(expected));
  await File(
    '${directory.path}/${stem}_diff_x8.png',
  ).writeAsBytes(image.encodePng(diffImage));
}
