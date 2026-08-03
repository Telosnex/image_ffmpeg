import 'dart:io';

import 'package:image_ffmpeg/image_ffmpeg.dart';

Future<void> main() async {
  final ffmpeg = await Ffmpeg.load();
  try {
    final encoded = await File(
      '../test/fixtures/image_formats/sources/test.jpg',
    ).readAsBytes();
    final decoded = await ffmpeg.decodeImage(
      encoded,
      maxWidth: 96,
      maxHeight: 96,
    );
    stdout.writeln('${decoded.width}x${decoded.height}');
  } finally {
    await ffmpeg.dispose();
  }
}
