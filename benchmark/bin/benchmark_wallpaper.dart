import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';

const _defaultInput =
    '/Users/jpo/Documents/Telosnex/wallpaper/'
    '019fbf46-5f54-7c0e-bef2-7dd87a5700a3.png';

Future<void> main(List<String> arguments) async {
  final path = arguments.isEmpty ? _defaultInput : arguments.single;
  final encoded = Uint8List.fromList(await File(path).readAsBytes());
  final ffmpeg = await Ffmpeg.load();
  try {
    stdout.writeln(ffmpeg.capabilities);
    if (!ffmpeg.capabilities.canDecodeImage) {
      stderr.writeln(
        'The bundled production artifact did not report FFmpeg support. '
        'Reinstall the package and verify native_artifacts/manifest.json.',
      );
      exitCode = 2;
      return;
    }

    const warmupRuns = 3;
    const measuredRuns = 10;
    for (var i = 0; i < warmupRuns; i++) {
      await ffmpeg.decodeImage(encoded, maxWidth: 96, maxHeight: 96);
    }

    final elapsedMicros = <int>[];
    RgbaImage? image;
    for (var i = 0; i < measuredRuns; i++) {
      final stopwatch = Stopwatch()..start();
      image = await ffmpeg.decodeImage(encoded, maxWidth: 96, maxHeight: 96);
      stopwatch.stop();
      elapsedMicros.add(stopwatch.elapsedMicroseconds);
    }
    elapsedMicros.sort();

    final mean =
        elapsedMicros.reduce((left, right) => left + right) / measuredRuns;
    stdout
      ..writeln(
        'Output: ${image!.width}x${image.height}, '
        '${image.bytes.length} RGBA bytes',
      )
      ..writeln(
        'Runs (ms): ${elapsedMicros.map((value) => (value / 1000).toStringAsFixed(3)).join(', ')}',
      )
      ..writeln('Min (ms): ${(elapsedMicros.first / 1000).toStringAsFixed(3)}')
      ..writeln(
        'Median (ms): '
        '${(elapsedMicros[measuredRuns ~/ 2] / 1000).toStringAsFixed(3)}',
      )
      ..writeln('Mean (ms): ${(mean / 1000).toStringAsFixed(3)}');
  } finally {
    await ffmpeg.dispose();
  }
}
