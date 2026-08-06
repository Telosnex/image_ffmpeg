import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import '_image_corpus_support.dart';

void main() {
  setUpAll(() async {
    if (!(await ImageFfmpeg.capabilities).canDecodeImage) {
      throw StateError('The malformed corpus requires a linked FFmpeg build.');
    }
  });

  group('malformed PNG never crashes or hangs', () {
    final corruptPngSuite = corpusFiles(
      'png',
      '.png',
    ).where((file) => file.uri.pathSegments.last.startsWith('x'));
    final brokenRegressions = corpusFiles('png/broken', '.png');

    for (final file in [...corruptPngSuite, ...brokenRegressions]) {
      final name = corpusRelativePath(file);
      test(name, () async {
        final bytes = await file.readAsBytes();
        await _probeWithoutCrashing(bytes);
        await _decodeWithoutCrashing(bytes);
      }, timeout: const Timeout(Duration(seconds: 10)));
    }
  });
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
    final decoded = await ImageFfmpeg.decodeImage(source);
    expectValidRgba(decoded);
  } on FfmpegException catch (error) {
    expect(error.status, isNegative);
  }
}
