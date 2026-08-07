@TestOn('browser')
library;

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import 'support/browser_test_support.dart';

void main() {
  test(
    'invalid pools fail initialization and do not poison retries',
    () async {
      ImageFfmpegWeb.workerCount = 0;
      await expectLater(ImageFfmpeg.capabilities, throwsRangeError);

      ImageFfmpegWeb.workerCount = 2;
      ImageFfmpegWeb.workerUri = Uri.parse(
        'support/abi_mismatch_worker.mjs',
      );
      await expectLater(
        ImageFfmpeg.capabilities,
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('ABI mismatch'),
        )),
      );

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
      ImageFfmpegWeb.workerCount = 2;
      ImageFfmpegWeb.workerUri = null;
    },
  );
}
