import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run bin/smoke_image_formats.dart <image>...');
    exitCode = 64;
    return;
  }

  final ffmpeg = await Ffmpeg.load();
  try {
    for (final path in arguments) {
      try {
        final image = await ffmpeg.decodeImage(
          Uint8List.fromList(await File(path).readAsBytes()),
          maxWidth: 96,
          maxHeight: 96,
        );
        stdout.writeln(
          '$path: ${image.width}x${image.height}, '
          '${image.bytes.length} RGBA bytes',
        );
      } on FfmpegException catch (error) {
        stderr.writeln('$path: $error');
        exitCode = 1;
      }
    }
  } finally {
    await ffmpeg.dispose();
  }
}
