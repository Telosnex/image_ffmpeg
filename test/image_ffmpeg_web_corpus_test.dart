@TestOn('browser')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import 'support/browser_pixel_matcher.dart';
import 'support/browser_test_support.dart';
import 'support/image_corpus_manifest.dart';

const _corpusRoot = 'fixtures/image_corpus';
const _formatRoot = 'fixtures/image_formats';

const _tiffKnownGaps = {
  'aspect32float.tif',
  'CNSW_crop.tif',
  'dtm32float.tif',
  'dtm64float.tif',
  'dtm_test.tif',
  'float1x32.tif',
  'tca32int.tif',
};

const _orientationBySuffix = {
  '1': ImageOrientation.normal,
  '2': ImageOrientation.flipHorizontal,
  '3': ImageOrientation.rotate180,
  '4': ImageOrientation.flipVertical,
  '5': ImageOrientation.transpose,
  '6': ImageOrientation.rotate90,
  '7': ImageOrientation.transverse,
  '8': ImageOrientation.rotate270,
};

void main() {
  setUpAll(() async {
    ImageFfmpegWeb.workerUri = servedWorkerUri;
    if (!(await ImageFfmpeg.capabilities).canDecodeImage) {
      throw StateError('The browser corpus requires the bundled Wasm build.');
    }
  });
  tearDownAll(() => ImageFfmpegWeb.workerUri = null);

  group('browser corpus integrity', () {
    test('generated fixture counts match the native corpus', () {
      expect(imageCorpusJpegFixtures, hasLength(62));
      expect(imageCorpusPngFixtures, hasLength(188));
      expect(imageCorpusApngFixtures, hasLength(5));
      expect(imageCorpusBrokenPngFixtures, hasLength(4));
      expect(imageCorpusGifFixtures, hasLength(12));
      expect(imageCorpusWebpFixtures, hasLength(30));
      expect(imageCorpusTiffFixtures, hasLength(26));
      expect(imageCorpusBmpFixtures, hasLength(10));
      expect(imageCorpusIcoFixtures, hasLength(3));
    });
  });

  group('JPEG corpus', () {
    for (final path in imageCorpusJpegFixtures) {
      test(path, () async {
        final bytes = await _fetchCorpusSource(path);
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.jpeg);
        expect(info.width, greaterThan(0));
        expect(info.height, greaterThan(0));

        final orientationMatch = RegExp(
          r'^(?:landscape|portrait)_([1-8])\.jpg$',
        ).firstMatch(_basename(path));
        if (orientationMatch != null) {
          final suffix = orientationMatch.group(1)!;
          expect(info.orientation, _orientationBySuffix[suffix]);
          final swapsAxes = const {'5', '6', '7', '8'}.contains(suffix);
          expect((
            info.displayWidth,
            info.displayHeight,
          ), swapsAxes ? (info.height, info.width) : (info.width, info.height));
        }

        final decoded = await ImageFfmpeg.decodeImage(bytes);
        _expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('valid PNG corpus', () {
    for (final path in imageCorpusPngFixtures.where(
      (path) => !_basename(path).startsWith('x'),
    )) {
      test(path, () async {
        await _expectProbeAndDecode(path, ImageFormat.png);
      });
    }
  });

  group('APNG first-frame corpus', () {
    for (final path in imageCorpusApngFixtures) {
      test(path, () async {
        await _expectProbeAndDecode(path, ImageFormat.apng);
      });
    }
  });

  group('GIF first-frame corpus', () {
    for (final path in imageCorpusGifFixtures) {
      test(path, () async {
        await _expectProbeAndDecode(path, ImageFormat.gif);
      });
    }
  });

  group('WebP first-frame corpus', () {
    for (final path in imageCorpusWebpFixtures) {
      test(path, () async {
        await _expectProbeAndDecode(path, ImageFormat.webp);
      });
    }
  });

  group('TIFF corpus', () {
    for (final path in imageCorpusTiffFixtures) {
      test(path, () async {
        final bytes = await _fetchCorpusSource(path);
        if (_tiffKnownGaps.contains(_basename(path))) {
          await expectLater(
            ImageFfmpeg.probeImage(bytes),
            throwsA(
              isA<FfmpegException>().having(
                (error) => error.status,
                'status',
                -5,
              ),
            ),
          );
          return;
        }
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.tiff);
        final decoded = await ImageFfmpeg.decodeImage(bytes);
        _expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  for (final format in const [
    ('BMP', ImageFormat.bmp, imageCorpusBmpFixtures),
    ('ICO', ImageFormat.ico, imageCorpusIcoFixtures),
  ]) {
    group('${format.$1} corpus', () {
      for (final path in format.$3) {
        test(path, () async {
          await _expectProbeAndDecode(path, format.$2);
        });
      }
    });
  }

  group('malformed PNG never crashes or hangs', () {
    final paths = [
      ...imageCorpusPngFixtures.where(
        (path) => _basename(path).startsWith('x'),
      ),
      ...imageCorpusBrokenPngFixtures,
    ];
    for (final path in paths) {
      test(path, () async {
        final source = await _fetchCorpusSource(path);
        await _probeWithoutCrashing(source);
        await _decodeWithoutCrashing(source);
      }, timeout: const Timeout(Duration(seconds: 10)));
    }
  });

  group('PNGSuite independent reference pixels', () {
    for (final path in imageCorpusPngFixtures.where((path) {
      final name = _basename(path);
      return name.startsWith('basi') || name.startsWith('basn');
    })) {
      test(path, () async {
        final name = _basename(path);
        await _compareCorpusReference(
          sourcePath: path,
          referencePath: 'references/imagemagick/png/$name',
          maxChannelDelta: 2,
          maxMeanChannelDelta: 0.5,
        );
      });
    }
  });

  group('APNG independent first-frame reference pixels', () {
    for (final path in imageCorpusApngFixtures) {
      test(path, () async {
        final name = _basename(path);
        await _compareCorpusReference(
          sourcePath: path,
          referencePath: 'references/imagemagick/apng/$name',
          maxChannelDelta: 2,
          maxMeanChannelDelta: 0.5,
        );
      });
    }
  });

  group('independent paired references', () {
    for (final comparison in const [
      _ReferenceCase(
        name: 'BMP alpha',
        source: 'bmp/alpha.bmp',
        reference: 'image/png/alpha.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'BMP buck_24',
        source: 'bmp/buck_24.bmp',
        reference: 'image/png/buck_24.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'WebP 2b',
        source: 'webp/2b.webp',
        reference: 'image/webp/2b.png',
        maxChannelDelta: 40,
        maxMeanChannelDelta: 1,
      ),
      _ReferenceCase(
        name: 'WebP error2',
        source: 'webp/error2.webp',
        reference: 'image/webp/error2.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'WebP test',
        source: 'webp/test.webp',
        reference: 'image/webp/test.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'JPEG buck_24',
        source: 'jpg/buck_24.jpg',
        reference: 'image/png/buck_24.png',
        maxChannelDelta: 80,
        maxMeanChannelDelta: 4,
      ),
      _ReferenceCase(
        name: 'GIF buck_24',
        source: 'gif/buck_24.gif',
        reference: 'image/png/buck_24.png',
        maxChannelDelta: 80,
        maxMeanChannelDelta: 8,
      ),
    ]) {
      test(comparison.name, () async {
        final actual = await ImageFfmpeg.decodeImage(
          await _fetchCorpusSource(comparison.source),
        );
        compareRgbaToPng(
          caseName: comparison.name,
          actual: actual,
          pngBytes: await fetchTestAsset(
            '$_corpusRoot/${comparison.reference}',
          ),
          maxChannelDelta: comparison.maxChannelDelta,
          maxMeanChannelDelta: comparison.maxMeanChannelDelta,
        );
      });
    }
  });

  group('JPEG test image family references', () {
    for (final name in const [
      'testimg.jpg',
      'testimgp.jpg',
      'testorig.jpg',
      'testprog.jpg',
    ]) {
      test(name, () async {
        final actual = await ImageFfmpeg.decodeImage(
          await _fetchCorpusSource('jpg/$name'),
        );
        compareRgbaToPng(
          caseName: 'JPEG_$name',
          actual: actual,
          pngBytes: await fetchTestAsset('$_corpusRoot/image/jpg/testimg.png'),
          maxChannelDelta: 64,
          maxMeanChannelDelta: 2,
        );
      });
    }
  });

  group('TIFF reviewed PNG regression goldens', () {
    for (final path in imageCorpusTiffFixtures.where(
      (path) => !_tiffKnownGaps.contains(_basename(path)),
    )) {
      test(path, () async {
        await _compareCorpusReference(
          sourcePath: path,
          referencePath: 'goldens/tiff/${_basename(path)}.png',
          maxChannelDelta: 0,
          maxMeanChannelDelta: 0,
        );
      });
    }
  });

  group('curated format corpus', () {
    for (final imageCase in _formatCases) {
      test('${imageCase.name}: probe metadata', () async {
        final info = await ImageFfmpeg.probeImage(
          await _fetchFormatSource(imageCase.source),
        );
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
          await _fetchFormatSource(imageCase.source),
        );
        _expectValidRgba(
          decoded,
          width: imageCase.width,
          height: imageCase.height,
        );
        compareRgbaToPng(
          caseName: imageCase.name,
          actual: decoded,
          pngBytes: await fetchTestAsset(
            '$_formatRoot/goldens/${imageCase.golden}',
          ),
          maxChannelDelta: imageCase.maxChannelDelta,
          maxMeanChannelDelta: imageCase.maxMeanChannelDelta,
        );
      });

      test('${imageCase.name}: fit-within scaling geometry', () async {
        final bytes = await _fetchFormatSource(imageCase.source);
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
  });
}

Future<void> _expectProbeAndDecode(String path, ImageFormat format) async {
  final bytes = await _fetchCorpusSource(path);
  final info = await ImageFfmpeg.probeImage(bytes);
  expect(info.format, format);
  final decoded = await ImageFfmpeg.decodeImage(bytes);
  _expectValidRgba(decoded, width: info.width, height: info.height);
}

void _expectValidRgba(RgbaImage decoded, {int? width, int? height}) {
  if (width != null) expect(decoded.width, width);
  if (height != null) expect(decoded.height, height);
  expect(decoded.width, greaterThan(0));
  expect(decoded.height, greaterThan(0));
  expect(decoded.stride, decoded.width * 4);
  expect(decoded.bytes.length, decoded.stride * decoded.height);
}

Future<void> _probeWithoutCrashing(Uint8List source) async {
  try {
    final info = await ImageFfmpeg.probeImage(source);
    expect(info.width, greaterThan(0));
    expect(info.height, greaterThan(0));
  } on FfmpegException catch (error) {
    expect(error.status, isNegative);
  }
}

Future<void> _decodeWithoutCrashing(Uint8List source) async {
  try {
    _expectValidRgba(await ImageFfmpeg.decodeImage(source));
  } on FfmpegException catch (error) {
    expect(error.status, isNegative);
  }
}

Future<void> _compareCorpusReference({
  required String sourcePath,
  required String referencePath,
  required int maxChannelDelta,
  required double maxMeanChannelDelta,
}) async {
  final actual = await ImageFfmpeg.decodeImage(
    await _fetchCorpusSource(sourcePath),
  );
  compareRgbaToPng(
    caseName: sourcePath,
    actual: actual,
    pngBytes: await fetchTestAsset('$_corpusRoot/$referencePath'),
    maxChannelDelta: maxChannelDelta,
    maxMeanChannelDelta: maxMeanChannelDelta,
  );
}

Future<Uint8List> _fetchCorpusSource(String path) =>
    fetchTestAsset('$_corpusRoot/image/$path');

Future<Uint8List> _fetchFormatSource(String path) =>
    fetchTestAsset('$_formatRoot/sources/$path');

String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

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

final class _ReferenceCase {
  const _ReferenceCase({
    required this.name,
    required this.source,
    required this.reference,
    required this.maxChannelDelta,
    required this.maxMeanChannelDelta,
  });

  final String name;
  final String source;
  final String reference;
  final int maxChannelDelta;
  final double maxMeanChannelDelta;
}

final class _FormatCase {
  const _FormatCase({
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

const _formatCases = [
  _FormatCase(
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
  _FormatCase(
    name: 'PNG',
    source: 'test.png',
    golden: 'verify_test_png.png',
    format: ImageFormat.png,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'APNG',
    source: 'test_animated.apng',
    golden: 'verify_test_apng.png',
    format: ImageFormat.apng,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'GIF',
    source: 'test_animated.gif',
    golden: 'verify_test_gif.png',
    format: ImageFormat.gif,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'BMP',
    source: 'test.bmp',
    golden: 'verify_test_bmp.png',
    format: ImageFormat.bmp,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'TIFF',
    source: 'test.tiff',
    golden: 'verify_test_tiff.png',
    format: ImageFormat.tiff,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'ICO',
    source: 'test.ico',
    golden: 'verify_test_ico.png',
    format: ImageFormat.ico,
    width: 32,
    height: 32,
    frameCount: 1,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'WebP',
    source: 'test.webp',
    golden: 'verify_test_webp.png',
    format: ImageFormat.webp,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'animated WebP',
    source: 'test_animated.webp',
    golden: 'verify_test_animated_webp.png',
    format: ImageFormat.webp,
    width: 800,
    height: 800,
    frameCount: 0,
    hasAlpha: true,
  ),
  _FormatCase(
    name: 'PSD',
    source: 'test.psd',
    golden: 'verify_test_psd.png',
    format: ImageFormat.psd,
    width: 800,
    height: 800,
    frameCount: 1,
    hasAlpha: true,
  ),
  _FormatCase(
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
