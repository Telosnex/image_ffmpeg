import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

const _fixtureRoot = '../test/fixtures/image_formats';
const _failureRoot = 'test/failures/image_formats';

final class _ImageCase {
  const _ImageCase({
    required this.name,
    required this.source,
    required this.golden,
    required this.format,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.hasAlpha,
    this.maxChannelDelta = 0,
    this.maxMeanChannelDelta = 0,
  });

  final String name;
  final String source;
  final String golden;
  final ImageFormat format;
  final int width;
  final int height;
  final int frameCount;
  final bool? hasAlpha;
  final int maxChannelDelta;
  final double maxMeanChannelDelta;
}

const _cases = [
  _ImageCase(
    name: 'JPEG',
    source: 'test.jpg',
    golden: 'verify_test_jpg.png',
    format: ImageFormat.jpeg,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: false,
    maxChannelDelta: 4,
    maxMeanChannelDelta: 0.05,
  ),
  _ImageCase(
    name: 'PNG',
    source: 'test.png',
    golden: 'verify_test_png.png',
    format: ImageFormat.png,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'APNG',
    source: 'test_animated.apng',
    golden: 'verify_test_apng.png',
    format: ImageFormat.apng,
    width: 800,
    height: 800,
    // FFmpeg exposes no nb_frames for APNG without decoding the stream.
    frameCount: 0,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'GIF',
    source: 'test_animated.gif',
    golden: 'verify_test_gif.png',
    format: ImageFormat.gif,
    width: 800,
    height: 800,
    // The reduced image-pipe demuxer does not advertise a frame count.
    frameCount: 0,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'BMP',
    source: 'test.bmp',
    golden: 'verify_test_bmp.png',
    format: ImageFormat.bmp,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'TIFF',
    source: 'test.tiff',
    golden: 'verify_test_tiff.png',
    format: ImageFormat.tiff,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'ICO',
    source: 'test.ico',
    golden: 'verify_test_ico.png',
    format: ImageFormat.ico,
    width: 32,
    height: 32,
    frameCount: 1,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'WebP',
    source: 'test.webp',
    golden: 'verify_test_webp.png',
    format: ImageFormat.webp,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'animated WebP',
    source: 'test_animated.webp',
    golden: 'verify_test_animated_webp.png',
    format: ImageFormat.webp,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'PSD',
    source: 'test.psd',
    golden: 'verify_test_psd.png',
    format: ImageFormat.psd,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _ImageCase(
    name: 'AVIF',
    source: 'kimono.avif',
    golden: 'verify_kimono_avif.png',
    format: ImageFormat.avif,
    width: 722,
    height: 1024,
    frameCount: 1,
    hasAlpha: false,
    maxChannelDelta: 4,
    maxMeanChannelDelta: 0.1,
  ),
];

void main() {
  setUpAll(() async {
    final failures = Directory(_failureRoot);
    if (failures.existsSync()) failures.deleteSync(recursive: true);
    if (!(await ImageFfmpeg.capabilities).canDecodeImage) {
      throw StateError(
        'The native conformance suite requires the bundled production '
        'FFmpeg artifact.',
      );
    }
  });

  group('format corpus', () {
    for (final imageCase in _cases) {
      test('${imageCase.name}: probe metadata', () async {
        final info = await ImageFfmpeg.probeImage(await _readSource(imageCase));

        expect(info.format, imageCase.format);
        expect((info.width, info.height), (imageCase.width, imageCase.height));
        expect(
          (info.displayWidth, info.displayHeight),
          (imageCase.width, imageCase.height),
        );
        expect(info.orientation, ImageOrientation.normal);
        expect(info.frameCount, imageCase.frameCount);
        expect(info.hasAlpha, imageCase.hasAlpha);
      });

      test('${imageCase.name}: full decode matches visual golden', () async {
        final decoded = await ImageFfmpeg.decodeImage(
          await _readSource(imageCase),
        );
        expect(
          (decoded.width, decoded.height),
          (imageCase.width, imageCase.height),
        );
        expect(decoded.stride, decoded.width * 4);
        expect(decoded.bytes.length, decoded.stride * decoded.height);

        final metrics = await _compareWithGolden(
          imageCase,
          decoded,
          imageCase.golden,
        );
        expect(
          metrics.maxChannelDelta,
          lessThanOrEqualTo(imageCase.maxChannelDelta),
          reason: metrics.toString(),
        );
        expect(
          metrics.meanChannelDelta,
          lessThanOrEqualTo(imageCase.maxMeanChannelDelta),
          reason: metrics.toString(),
        );
      });

      test('${imageCase.name}: fit-within scaling geometry', () async {
        final bytes = await _readSource(imageCase);
        final boxed = await ImageFfmpeg.decodeImage(
          bytes,
          maxWidth: 96,
          maxHeight: 96,
        );
        expect((
          boxed.width,
          boxed.height,
        ), _fitWithin(imageCase.width, imageCase.height, 96, 96));
        expect(boxed.stride, boxed.width * 4);

        final widthOnly = await ImageFfmpeg.decodeImage(bytes, maxWidth: 96);
        expect((
          widthOnly.width,
          widthOnly.height,
        ), _fitWithin(imageCase.width, imageCase.height, 96, 0));

        final noUpscale = await ImageFfmpeg.decodeImage(
          bytes,
          maxWidth: imageCase.width * 2,
          maxHeight: imageCase.height * 2,
        );
        expect(
          (noUpscale.width, noUpscale.height),
          (imageCase.width, imageCase.height),
        );
      });
    }

    test(
      'APNG: probe reports the advertised frame count',
      () async {
        final bytes = await File(
          '$_fixtureRoot/sources/test_animated.apng',
        ).readAsBytes();
        expect((await ImageFfmpeg.probeImage(bytes)).frameCount, 2);
      },
      skip: 'Probe does not parse APNG acTL; FFmpeg reports nb_frames as zero.',
    );

    test(
      'GIF: probe reports the advertised frame count',
      () async {
        final bytes = await File(
          '$_fixtureRoot/sources/test_animated.gif',
        ).readAsBytes();
        expect((await ImageFfmpeg.probeImage(bytes)).frameCount, 2);
      },
      skip: 'The reduced image-pipe demuxer reports nb_frames as zero.',
    );
  });
}

Future<Uint8List> _readSource(_ImageCase imageCase) =>
    File('$_fixtureRoot/sources/${imageCase.source}').readAsBytes();

(int, int) _fitWithin(int width, int height, int maxWidth, int maxHeight) {
  if ((maxWidth == 0 || width <= maxWidth) &&
      (maxHeight == 0 || height <= maxHeight)) {
    return (width, height);
  }
  if (maxWidth != 0 &&
      (maxHeight == 0 || maxWidth * height <= maxHeight * width)) {
    return (maxWidth, math.max(1, height * maxWidth ~/ width));
  }
  return (math.max(1, width * maxHeight ~/ height), maxHeight);
}

final class _PixelMetrics {
  const _PixelMetrics({
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
      '$differingPixels/$pixelCount; inspect $_failureRoot';
}

Future<_PixelMetrics> _compareWithGolden(
  _ImageCase imageCase,
  RgbaImage actual,
  String goldenName,
) async {
  final goldenBytes = await File(
    '$_fixtureRoot/goldens/$goldenName',
  ).readAsBytes();
  final expectedImage = img.decodePng(goldenBytes);
  if (expectedImage == null) throw StateError('Cannot decode $goldenName');
  if (expectedImage.width != actual.width ||
      expectedImage.height != actual.height) {
    throw StateError(
      '$goldenName is ${expectedImage.width}x${expectedImage.height}; '
      'actual is ${actual.width}x${actual.height}',
    );
  }

  final expected = expectedImage.getBytes(order: img.ChannelOrder.rgba);
  final diff = Uint8List(actual.width * actual.height * 4);
  var maxDelta = 0;
  var totalDelta = 0;
  var differingPixels = 0;
  for (var pixel = 0; pixel < actual.width * actual.height; pixel++) {
    final actualOffset =
        (pixel ~/ actual.width) * actual.stride + (pixel % actual.width) * 4;
    final expectedOffset = pixel * 4;
    var pixelDiffers = false;
    final actualAlpha = actual.bytes[actualOffset + 3];
    final expectedAlpha = expected[expectedOffset + 3];
    for (var channel = 0; channel < 4; channel++) {
      // RGB beneath zero alpha is invisible and decoders may choose different
      // fill values. Premultiplication compares visible colour plus alpha.
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

  final metrics = _PixelMetrics(
    maxChannelDelta: maxDelta,
    meanChannelDelta: totalDelta / (actual.width * actual.height * 4),
    differingPixels: differingPixels,
    pixelCount: actual.width * actual.height,
  );
  if (metrics.maxChannelDelta > imageCase.maxChannelDelta ||
      metrics.meanChannelDelta > imageCase.maxMeanChannelDelta) {
    await _writeFailureImages(imageCase, actual, expectedImage, diff);
  }
  return metrics;
}

Future<void> _writeFailureImages(
  _ImageCase imageCase,
  RgbaImage actual,
  img.Image expected,
  Uint8List diff,
) async {
  final directory = Directory(_failureRoot)..createSync(recursive: true);
  final stem = imageCase.name.toLowerCase();
  final actualImage = img.Image.fromBytes(
    width: actual.width,
    height: actual.height,
    bytes: actual.bytes.buffer,
    bytesOffset: actual.bytes.offsetInBytes,
    rowStride: actual.stride,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final diffImage = img.Image.fromBytes(
    width: actual.width,
    height: actual.height,
    bytes: diff.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  await File(
    '${directory.path}/${stem}_actual.png',
  ).writeAsBytes(img.encodePng(actualImage));
  await File(
    '${directory.path}/${stem}_expected.png',
  ).writeAsBytes(img.encodePng(expected));
  await File(
    '${directory.path}/${stem}_diff_x8.png',
  ).writeAsBytes(img.encodePng(diffImage));
}
