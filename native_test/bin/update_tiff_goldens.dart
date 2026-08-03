import 'dart:io';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:image/image.dart' as image;

const _sourceDirectory = '../test/fixtures/image_corpus/image/tiff';
const _goldenDirectory = '../test/fixtures/image_corpus/goldens/tiff';

/// TIFFs intentionally pinned as unsupported by the native conformance suite.
const _unsupported = {
  'aspect32float.tif',
  'CNSW_crop.tif',
  'dtm32float.tif',
  'dtm64float.tif',
  'dtm_test.tif',
  'float1x32.tif',
  'tca32int.tif',
};

Future<void> main() async {
  final outputDirectory = Directory(_goldenDirectory);
  if (outputDirectory.existsSync()) {
    outputDirectory.deleteSync(recursive: true);
  }
  outputDirectory.createSync(recursive: true);

  final sources =
      Directory(_sourceDirectory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.tif'))
          .where((file) => !_unsupported.contains(file.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final ffmpeg = await Ffmpeg.load();
  if (!ffmpeg.capabilities.canDecodeImage) {
    throw StateError('This tool requires the native linked-FFmpeg harness.');
  }

  try {
    for (final source in sources) {
      final decoded = await ffmpeg.decodeImage(await source.readAsBytes());
      final rgba = image.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: decoded.bytes.buffer,
        bytesOffset: decoded.bytes.offsetInBytes,
        rowStride: decoded.stride,
        numChannels: 4,
        order: image.ChannelOrder.rgba,
      );
      final name = source.uri.pathSegments.last;
      final output = File('$_goldenDirectory/$name.png');
      await output.writeAsBytes(image.encodePng(rgba));
      stdout.writeln('$name -> ${output.path}');
    }
  } finally {
    await ffmpeg.dispose();
  }

  if (sources.length != 19) {
    throw StateError(
      'Expected 19 decodable TIFF fixtures, found ${sources.length}.',
    );
  }
}
