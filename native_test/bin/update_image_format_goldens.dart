import 'dart:io';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:image/image.dart' as img;

const _fixtureRoot = '../test/fixtures/image_formats';

// verify_test_animated_webp.png is an independent ImageMagick reference and
// is intentionally not overwritten by this package's decoder.
const _fixtures = {
  'test.jpg': 'verify_test_jpg.png',
  'test.png': 'verify_test_png.png',
  'test_animated.apng': 'verify_test_apng.png',
  'test_animated.gif': 'verify_test_gif.png',
  'test.bmp': 'verify_test_bmp.png',
  'test.tiff': 'verify_test_tiff.png',
  'test.ico': 'verify_test_ico.png',
  'test.webp': 'verify_test_webp.png',
  'test.psd': 'verify_test_psd.png',
  'kimono.avif': 'verify_kimono_avif.png',
};

Future<void> main() async {
  final ffmpeg = await Ffmpeg.load();
  if (!ffmpeg.capabilities.canDecodeImage) {
    throw StateError('This tool requires the native linked-FFmpeg harness.');
  }

  try {
    for (final entry in _fixtures.entries) {
      final encoded = await File(
        '$_fixtureRoot/sources/${entry.key}',
      ).readAsBytes();
      final decoded = await ffmpeg.decodeImage(encoded);
      final image = img.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: decoded.bytes.buffer,
        bytesOffset: decoded.bytes.offsetInBytes,
        rowStride: decoded.stride,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      final output = File('$_fixtureRoot/goldens/${entry.value}');
      await output.writeAsBytes(img.encodePng(image));
      stdout.writeln('${entry.key} -> ${output.path}');
    }
  } finally {
    await ffmpeg.dispose();
  }
}
