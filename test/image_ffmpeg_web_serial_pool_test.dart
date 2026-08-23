@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

Uint8List _requestBytes(int delay, int value, List<int> marker) =>
    Uint8List.fromList([delay, value, ...marker]);

void main() {
  setUpAll(() {
    ImageFfmpegWeb.workerCount = 1;
    ImageFfmpegWeb.workerUri = Uri.parse('support/pool_test_worker.mjs');
  });

  tearDownAll(() {
    ImageFfmpegWeb.workerCount = 2;
    ImageFfmpegWeb.workerUri = null;
  });

  test('one Worker runs operations serially', () async {
    final marker = List<int>.generate(
      6,
      (index) => DateTime.now().microsecondsSinceEpoch >> (index * 8) & 0xff,
    );

    final results = await Future.wait([
      ImageFfmpeg.probeImage(_requestBytes(60, 10, marker)),
      ImageFfmpeg.probeImage(_requestBytes(60, 11, marker)),
    ]);

    expect(results.map((result) => result.width), [10, 11]);
  });

  test(
    'the central queue dispatches waiting operations in FIFO order',
    () async {
      final completionOrder = <int>[];
      Future<void> run(int delay, int value) async {
        await ImageFfmpeg.probeImage(
          _requestBytes(delay, value, [value, 91, 37]),
        );
        completionOrder.add(value);
      }

      await Future.wait([run(80, 10), run(0, 20), run(0, 30), run(0, 40)]);
      expect(completionOrder, [10, 20, 30, 40]);
    },
  );

  test('an FFmpeg error does not stop its Worker', () async {
    await expectLater(
      ImageFfmpeg.probeImage(_requestBytes(254, 1, [2, 3, 4])),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -6),
      ),
    );

    final result = await ImageFfmpeg.probeImage(
      _requestBytes(0, 73, [5, 6, 7]),
    );
    expect(result.width, 73);
  });

  test('a failed Worker is replaced once', () async {
    final failed = expectLater(
      ImageFfmpeg.probeImage(_requestBytes(255, 1, [8, 9, 10])),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -2),
      ),
    );
    final queued = ImageFfmpeg.probeImage(_requestBytes(0, 83, [11, 12, 13]));

    await failed;
    expect((await queued).width, 83);
  });
}
