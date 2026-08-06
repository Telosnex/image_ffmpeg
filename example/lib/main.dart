import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_ffmpeg/image_ffmpeg.dart';

void main() => runApp(const ExampleApp());

/// Loads the bundled FFmpeg, then round-trips a generated gradient through
/// PNG encode -> probe -> scaled decode without any platform-specific code.
Future<String> _demonstrate() async {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      pixels.setAll((y * size + x) * 4, [
        x * 255 ~/ (size - 1),
        y * 255 ~/ (size - 1),
        0x80,
        0xff,
      ]);
    }
  }
  final gradient = RgbaImage(
    width: size,
    height: size,
    stride: size * 4,
    bytes: pixels,
  );

  final png = await ImageFfmpeg.encodePng(gradient);
  final info = await ImageFfmpeg.probeImage(png);
  final decoded = await ImageFfmpeg.decodeImage(
    png,
    maxWidth: 32,
    maxHeight: 32,
  );
  final capabilities = await ImageFfmpeg.capabilities;
  final report =
      '$capabilities\n\n'
      'Encoded a ${size}x$size gradient into a ${png.length}-byte '
      '${info.format.name.toUpperCase()}, then decoded it back at '
      '${decoded.width}x${decoded.height}.\n\n'
      'Pinned reduced FFmpeg is bundled and ready.';
  debugPrint('image_ffmpeg example: $report');
  return report;
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('image_ffmpeg')),
      body: FutureBuilder<String>(
        future: _demonstrate(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Load failed: ${snapshot.error}'));
          }
          final report = snapshot.data;
          if (report == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(report, textAlign: TextAlign.center),
            ),
          );
        },
      ),
    ),
  );
}
