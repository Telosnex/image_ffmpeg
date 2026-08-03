import 'dart:io';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '_image_corpus_support.dart';

const _tiffKnownGaps = {
  'aspect32float.tif',
  'CNSW_crop.tif',
  'dtm32float.tif',
  'dtm64float.tif',
  'dtm_test.tif',
  'float1x32.tif',
  'float32.tif',
  'tca32int.tif',
};

void main() {
  late Ffmpeg ffmpeg;

  setUpAll(() async {
    ffmpeg = await Ffmpeg.load();
    if (!ffmpeg.capabilities.canDecodeImage) {
      throw StateError('Reference comparisons require a linked FFmpeg build.');
    }
    final failures = Directory(corpusFailureRoot);
    if (failures.existsSync()) failures.deleteSync(recursive: true);
  });
  tearDownAll(() => ffmpeg.dispose());

  group('PNGSuite baseline pixels', () {
    final baselineFiles = corpusFiles('png', '.png').where((file) {
      final name = file.uri.pathSegments.last;
      return name.startsWith('basi') || name.startsWith('basn');
    });
    for (final file in baselineFiles) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        await _compareSourceWithPngReference(
          ffmpeg,
          source: file,
          reference: File(
            '../test/fixtures/image_corpus/references/imagemagick/png/$name',
          ),
          maxChannelDelta: 2,
          maxMeanChannelDelta: 0.5,
        );
      });
    }
  });

  group('APNG first-frame pixels', () {
    for (final file in corpusFiles(
      'png/apng',
      '.png',
    ).where((file) => !file.path.endsWith('test_apng2.png'))) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        await _compareSourceWithPngReference(
          ffmpeg,
          source: file,
          reference: File(
            '../test/fixtures/image_corpus/references/imagemagick/apng/$name',
          ),
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
        reference: 'png/alpha.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'BMP buck_24',
        source: 'bmp/buck_24.bmp',
        reference: 'png/buck_24.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'WebP 2b',
        source: 'webp/2b.webp',
        reference: 'webp/2b.png',
        maxChannelDelta: 40,
        maxMeanChannelDelta: 1,
      ),
      _ReferenceCase(
        name: 'WebP error2',
        source: 'webp/error2.webp',
        reference: 'webp/error2.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'WebP test',
        source: 'webp/test.webp',
        reference: 'webp/test.png',
        maxChannelDelta: 0,
        maxMeanChannelDelta: 0,
      ),
      _ReferenceCase(
        name: 'JPEG buck_24',
        source: 'jpg/buck_24.jpg',
        reference: 'png/buck_24.png',
        maxChannelDelta: 80,
        maxMeanChannelDelta: 4,
      ),
      _ReferenceCase(
        name: 'GIF buck_24',
        source: 'gif/buck_24.gif',
        reference: 'png/buck_24.png',
        maxChannelDelta: 80,
        maxMeanChannelDelta: 8,
      ),
    ]) {
      test(comparison.name, () async {
        final source = File('$corpusRoot/${comparison.source}');
        final reference = image.decodePng(
          await File('$corpusRoot/${comparison.reference}').readAsBytes(),
        );
        if (reference == null) {
          throw StateError('Cannot decode ${comparison.reference}');
        }
        await compareRgbaToReference(
          caseName: comparison.name,
          actual: await ffmpeg.decodeImage(await source.readAsBytes()),
          reference: reference,
          maxChannelDelta: comparison.maxChannelDelta,
          maxMeanChannelDelta: comparison.maxMeanChannelDelta,
        );
      });
    }
  });

  group('JPEG test image family', () {
    final reference = image.decodePng(
      File('$corpusRoot/jpg/testimg.png').readAsBytesSync(),
    );
    if (reference == null) throw StateError('Cannot decode jpg/testimg.png');
    for (final name in const [
      'testimg.jpg',
      'testimgp.jpg',
      'testorig.jpg',
      'testprog.jpg',
    ]) {
      test(name, () async {
        final source = File('$corpusRoot/jpg/$name');
        await compareRgbaToReference(
          caseName: 'JPEG_$name',
          actual: await ffmpeg.decodeImage(await source.readAsBytes()),
          reference: reference,
          maxChannelDelta: 64,
          maxMeanChannelDelta: 2,
        );
      });
    }
  });

  group('TIFF reviewed PNG regression goldens', () {
    for (final file in corpusFiles(
      'tiff',
      '.tif',
    ).where((file) => !_tiffKnownGaps.contains(file.uri.pathSegments.last))) {
      final name = file.uri.pathSegments.last;
      test(name, () async {
        await _compareSourceWithPngReference(
          ffmpeg,
          source: file,
          reference: File(
            '../test/fixtures/image_corpus/goldens/tiff/$name.png',
          ),
          maxChannelDelta: 0,
          maxMeanChannelDelta: 0,
        );
      });
    }
  });
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

Future<void> _compareSourceWithPngReference(
  Ffmpeg ffmpeg, {
  required File source,
  required File reference,
  required int maxChannelDelta,
  required double maxMeanChannelDelta,
}) async {
  final bytes = await source.readAsBytes();
  final referenceImage = image.decodePng(await reference.readAsBytes());
  if (referenceImage == null) {
    throw StateError('Cannot decode reference ${reference.path}');
  }
  await compareRgbaToReference(
    caseName: corpusRelativePath(source),
    actual: await ffmpeg.decodeImage(bytes),
    reference: referenceImage,
    maxChannelDelta: maxChannelDelta,
    maxMeanChannelDelta: maxMeanChannelDelta,
  );
}
