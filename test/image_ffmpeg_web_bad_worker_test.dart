@TestOn('browser')
library;

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import 'support/browser_test_support.dart';

void main() {
  test(
    'a failed Worker load is diagnosable and does not poison retries',
    () async {
      ImageFfmpegWeb.workerUri = Uri.parse(
        'packages/image_ffmpeg/web/missing.mjs',
      );
      await expectLater(
        ImageFfmpeg.capabilities,
        throwsA(
          isA<FfmpegException>()
              .having((error) => error.status, 'status', -2)
              .having(
                (error) => error.message,
                'message',
                contains('missing.mjs'),
              ),
        ),
      );

      ImageFfmpegWeb.workerUri = servedWorkerUri;
      expect(
        (await ImageFfmpeg.capabilities).runtime,
        FfmpegRuntime.webAssembly,
      );
    },
  );
}
