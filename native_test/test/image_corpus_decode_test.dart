import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import '_image_corpus_support.dart';

const _tiffProbeUnsupported = {
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
    if (!(await ImageFfmpeg.capabilities).canDecodeImage) {
      throw StateError('The image corpus requires a linked FFmpeg build.');
    }
  });

  group('corpus integrity', () {
    test('expected fixture counts', () {
      expect(corpusFiles('jpg', '.jpg'), hasLength(62));
      expect(corpusFiles('png', '.png'), hasLength(188));
      expect(corpusFiles('png/apng', '.png'), hasLength(5));
      expect(corpusFiles('png/broken', '.png'), hasLength(4));
      expect(corpusFiles('gif', '.gif'), hasLength(12));
      expect(corpusFiles('webp', '.webp'), hasLength(30));
      expect(corpusFiles('tiff', '.tif'), hasLength(26));
      expect(corpusFiles('bmp', '.bmp'), hasLength(10));
      expect(corpusFiles('ico', '.ico'), hasLength(3));
    });
  });

  group('JPEG corpus', () {
    for (final file in corpusFiles('jpg', '.jpg')) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.jpeg);
        expect(info.width, greaterThan(0));
        expect(info.height, greaterThan(0));

        final orientationMatch = RegExp(
          r'^(?:landscape|portrait)_([1-8])\.jpg$',
        ).firstMatch(name);
        if (orientationMatch != null) {
          expect(
            info.orientation,
            _orientationBySuffix[orientationMatch.group(1)],
          );
          final swapsAxes = const {
            '5',
            '6',
            '7',
            '8',
          }.contains(orientationMatch.group(1));
          expect((
            info.displayWidth,
            info.displayHeight,
          ), swapsAxes ? (info.height, info.width) : (info.width, info.height));
        }

        final decoded = await ImageFfmpeg.decodeImage(bytes);
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('valid PNG corpus', () {
    final validPngs = corpusFiles(
      'png',
      '.png',
    ).where((file) => !file.uri.pathSegments.last.startsWith('x'));
    for (final file in validPngs) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.png);
        final decoded = await ImageFfmpeg.decodeImage(bytes);
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('APNG first-frame corpus', () {
    for (final file in corpusFiles('png/apng', '.png')) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.apng);
        final decoded = await ImageFfmpeg.decodeImage(bytes);
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('GIF first-frame corpus', () {
    for (final file in corpusFiles('gif', '.gif')) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.gif);
        final decoded = await ImageFfmpeg.decodeImage(bytes);
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('WebP corpus', () {
    for (final file in corpusFiles('webp', '.webp')) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        final info = await ImageFfmpeg.probeImage(bytes);
        expect(info.format, ImageFormat.webp);
        final decoded = await ImageFfmpeg.decodeImage(bytes);
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  group('TIFF corpus', () {
    for (final file in corpusFiles('tiff', '.tif')) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        final bytes = await file.readAsBytes();
        if (_tiffProbeUnsupported.contains(name)) {
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
        expectValidRgba(decoded, width: info.width, height: info.height);
      });
    }
  });

  for (final format in const [
    ('BMP', 'bmp', '.bmp', ImageFormat.bmp),
    ('ICO', 'ico', '.ico', ImageFormat.ico),
  ]) {
    group('${format.$1} corpus', () {
      for (final file in corpusFiles(format.$2, format.$3)) {
        final name = file.uri.pathSegments.last;
        test(name, () async {
          final bytes = await file.readAsBytes();
          final info = await ImageFfmpeg.probeImage(bytes);
          expect(info.format, format.$4);
          final decoded = await ImageFfmpeg.decodeImage(bytes);
          expectValidRgba(decoded, width: info.width, height: info.height);
        });
      }
    });
  }
}
