import 'package:image_ffmpeg/image_ffmpeg.dart';

import 'browser_test_support.dart';

void configureSyntheticTestPlatform() {
  ImageFfmpegWeb.workerUri = servedWorkerUri;
}
