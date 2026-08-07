@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

Uint8List _requestBytes(int delay, int value, List<int> marker) =>
    Uint8List.fromList([delay, value, ...marker]);

void main() {
  setUpAll(() {
    ImageFfmpegWeb.workerCount = 2;
    ImageFfmpegWeb.workerUri = Uri.parse('support/pool_test_worker.mjs');
  });

  tearDownAll(() {
    ImageFfmpegWeb.workerCount = 2;
    ImageFfmpegWeb.workerUri = null;
  });

  test('two operations overlap with two Workers', () async {
    final marker = List<int>.generate(
      6,
      (index) => DateTime.now().microsecondsSinceEpoch >> (index * 8) & 0xff,
    );

    final results = await Future.wait([
      ImageFfmpeg.probeImage(_requestBytes(80, 10, marker)),
      ImageFfmpeg.probeImage(_requestBytes(80, 11, marker)),
    ]);

    expect(results.map((result) => result.width), contains(2));
  });

  test('the central queue dispatches waiting operations in FIFO order', () async {
    final completionOrder = <int>[];
    Future<void> run(int delay, int value) async {
      await ImageFfmpeg.probeImage(
        _requestBytes(delay, value, [value, 91, 37]),
      );
      completionOrder.add(value);
    }

    await Future.wait([
      run(240, 10),
      run(80, 20),
      run(80, 30),
      run(0, 40),
    ]);

    expect(completionOrder, [20, 30, 40, 10]);
  });

  test('the pool snapshots bytes before a queued operation starts', () async {
    final blocker = ImageFfmpeg.probeImage(
      _requestBytes(80, 50, [1, 2, 3]),
    );
    final secondBlocker = ImageFfmpeg.probeImage(
      _requestBytes(80, 51, [4, 5, 6]),
    );
    final bytes = _requestBytes(0, 77, [7, 8, 9]);
    final queued = ImageFfmpeg.probeImage(bytes);
    bytes[1] = 99;

    final result = await queued;
    await Future.wait([blocker, secondBlocker]);
    expect(result.width, 77);
    expect(bytes[1], 99);
  });
}
