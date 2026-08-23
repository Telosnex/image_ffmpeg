// Reproduce a versioned operation recipe as viewable source/actual/expected
// images without checking opaque raster goldens into the package.
//
// dart run tool/render_synthetic_operation.dart --list
// dart run tool/render_synthetic_operation.dart v1/crop-bottom-right /tmp/case
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:image_ffmpeg/image_ffmpeg.dart';

import 'support/synthetic_operation_corpus.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--list') {
    stdout.writeAll(syntheticOperationIds, '\n');
    stdout.writeln();
    return;
  }
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/render_synthetic_operation.dart '
      '<v$syntheticOperationCorpusVersion/case> <output-directory>\n'
      '       dart run tool/render_synthetic_operation.dart --list',
    );
    exitCode = 64;
    return;
  }
  final id = arguments[0].startsWith('v')
      ? arguments[0]
      : 'v$syntheticOperationCorpusVersion/${arguments[0]}';
  if (!syntheticOperationIds.contains(id)) {
    stderr.writeln('Unknown recipe: $id (use --list)');
    exitCode = 64;
    return;
  }
  final directory = Directory(arguments[1])..createSync(recursive: true);
  final landscape = buildSyntheticSource(width: 17, height: 13, seed: 0x170d);
  final portrait = buildSyntheticSource(width: 11, height: 19, seed: 0x0b13);
  SyntheticSource source = landscape;
  RgbaImage? actual;
  RgbaImage? expected;

  if (id.startsWith('v1/decode-prime-')) {
    source = switch (id) {
      'v1/decode-prime-17x13' => landscape,
      'v1/decode-prime-19x11' => buildSyntheticSource(
        width: 19,
        height: 11,
        seed: 0x130b,
      ),
      _ => buildSyntheticSource(width: 23, height: 17, seed: 0x1711),
    };
    actual = await ImageFfmpeg.decodeImage(source.png);
    expected = _tight(source.rgba, source.width, source.height);
  } else if (id.startsWith('v1/encode-padding-')) {
    final padding = int.parse(id.split('-').last);
    final encoded = await ImageFfmpeg.encodePng(paddedRgba(source, padding));
    actual = await ImageFfmpeg.decodeImage(encoded);
    expected = _tight(source.rgba, source.width, source.height);
  } else if (id.startsWith('v1/crop-') && id != 'v1/crop-fit-prime-rounding') {
    final crop = switch (id) {
      'v1/crop-top-left' => const ImageCrop(x: 0, y: 0, width: 7, height: 5),
      'v1/crop-bottom-right' => const ImageCrop(
        x: 10,
        y: 8,
        width: 7,
        height: 5,
      ),
      'v1/crop-one-pixel' => const ImageCrop(x: 16, y: 12, width: 1, height: 1),
      _ => const ImageCrop(x: 2, y: 3, width: 11, height: 7),
    };
    final result = await ImageFfmpeg.transcodeImage(
      source.png,
      output: const ImageOutput.png(),
      applyOrientation: false,
      crop: crop,
    );
    actual = await ImageFfmpeg.decodeImage(result.bytes);
    expected = _tight(cropRgba(source, crop), crop.width, crop.height);
  } else if (id.startsWith('v1/fill-')) {
    final fill = switch (id) {
      'v1/fill-top-edge' => const ImageFillRect(
        x: 0,
        y: 0,
        width: 17,
        height: 2,
        color: 0xffff0080,
      ),
      'v1/fill-bottom-right' => const ImageFillRect(
        x: 12,
        y: 9,
        width: 5,
        height: 4,
        color: 0xff204060,
      ),
      'v1/fill-one-pixel' => const ImageFillRect(
        x: 8,
        y: 6,
        width: 1,
        height: 1,
        color: 0xff010203,
      ),
      _ => const ImageFillRect(
        x: 3,
        y: 4,
        width: 7,
        height: 5,
        color: 0x00123456,
      ),
    };
    final result = await ImageFfmpeg.fillRectangle(
      source.png,
      rectangle: fill,
      output: const ImageOutput.png(),
    );
    actual = await ImageFfmpeg.decodeImage(result.bytes);
    expected = _tight(fillRgba(source, fill), source.width, source.height);
  } else if (id.startsWith('v1/box-')) {
    source = id.endsWith('portrait') ? portrait : landscape;
    final mode = id.contains('opaque')
        ? BoxAverageAlphaMode.opaqueOnly
        : BoxAverageAlphaMode.include;
    actual = await ImageFfmpeg.decodeImageBoxAverage(
      source.png,
      maxDimension: 7,
      alphaMode: mode,
    );
    expected = boxAverage(source, 7, mode);
  } else if (id == 'v1/passthrough-png') {
    final result = await ImageFfmpeg.transcodeImage(
      source.png,
      output: const ImageOutput.png(),
      passthroughIfUnchanged: true,
    );
    actual = await ImageFfmpeg.decodeImage(result.bytes);
    expected = _tight(source.rgba, source.width, source.height);
  } else if (id == 'v1/crop-fit-prime-rounding') {
    final result = await ImageFfmpeg.transcodeImage(
      source.png,
      output: const ImageOutput.png(),
      applyOrientation: false,
      crop: const ImageCrop(x: 1, y: 1, width: 15, height: 11),
      maxWidth: 11,
      maxHeight: 7,
    );
    actual = await ImageFfmpeg.decodeImage(result.bytes);
  } else {
    const width = 8;
    const height = 8;
    final rgba = Uint8List(width * height * 4);
    for (var offset = 0; offset < rgba.length; offset += 4) {
      rgba[offset] = 240;
      rgba[offset + 1] = 3;
      rgba[offset + 2] = 190;
    }
    final encoded = await ImageFfmpeg.encodeJpeg(
      _tight(rgba, width, height),
      quality: 100,
      chroma: JpegChroma.yuv444,
      backgroundColor: 0xff102030,
    );
    actual = await ImageFfmpeg.decodeImage(encoded);
  }

  await File('${directory.path}/source.png').writeAsBytes(source.png);
  await _writeRgba('${directory.path}/actual.png', actual);
  if (expected != null) {
    await _writeRgba('${directory.path}/expected.png', expected);
    if (actual.width == expected.width && actual.height == expected.height) {
      final diff = Uint8List(actual.bytes.length);
      for (var index = 0; index < diff.length; index++) {
        final delta = (actual.bytes[index] - expected.bytes[index]).abs();
        diff[index] = (delta * 8).clamp(0, 255);
      }
      await _writeRgba(
        '${directory.path}/diff_x8.png',
        _tight(diff, actual.width, actual.height),
      );
    }
  }
  stdout.writeln('wrote $id to ${directory.path}');
}

RgbaImage _tight(Uint8List rgba, int width, int height) =>
    RgbaImage(width: width, height: height, stride: width * 4, bytes: rgba);

Future<void> _writeRgba(String path, RgbaImage rgba) => File(path).writeAsBytes(
  image.encodePng(
    image.Image.fromBytes(
      width: rgba.width,
      height: rgba.height,
      bytes: rgba.bytes.buffer,
      numChannels: 4,
      order: image.ChannelOrder.rgba,
      rowStride: rgba.stride,
    ),
  ),
);
