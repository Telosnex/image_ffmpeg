@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import 'support/browser_test_support.dart';

Future<Uint8List> _fetchFixture(String name) =>
    fetchTestAsset('fixtures/image_formats/sources/$name');

void main() {
  setUpAll(() => ImageFfmpegWeb.workerUri = servedWorkerUri);
  tearDownAll(() => ImageFfmpegWeb.workerUri = null);

  test('loads the Wasm worker and reports capabilities', () async {
    final capabilities = await ImageFfmpeg.capabilities;
    expect(capabilities.runtime, FfmpegRuntime.webAssembly);
    expect(capabilities.abiVersion, 5);
    expect(capabilities.canDecodeImage, isTrue);
    expect(capabilities.canEncodeJpeg, isTrue);
    expect(capabilities.canEncodePng, isTrue);
    expect(capabilities.buildInfo, contains('Lavc63.1.100'));
  });

  test('probes and decodes the first animated WebP frame', () async {
    final bytes = await _fetchFixture('test_animated.webp');

    final info = await ImageFfmpeg.probeImage(bytes);
    expect(info.format, ImageFormat.webp);
    expect((info.width, info.height), (800, 800));
    expect(info.hasAlpha, isTrue);

    final image = await ImageFfmpeg.decodeImage(
      bytes,
      maxWidth: 96,
      maxHeight: 96,
    );
    expect((image.width, image.height), (96, 96));
    expect(image.bytes.length, 96 * 96 * 4);
  });

  test('decode does not clobber the caller-visible input bytes', () async {
    final bytes = await _fetchFixture('test.jpg');
    final before = Uint8List.fromList(bytes);
    await ImageFfmpeg.decodeImage(bytes, maxWidth: 32, maxHeight: 32);
    expect(bytes, before);
  });

  test('round-trips decode -> encodePng -> probe -> decode', () async {
    final jpeg = await _fetchFixture('test.jpg');

    final image = await ImageFfmpeg.decodeImage(
      jpeg,
      maxWidth: 64,
      maxHeight: 64,
    );
    final png = await ImageFfmpeg.encodePng(image, compressionLevel: 6);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);

    final info = await ImageFfmpeg.probeImage(png);
    expect(info.format, ImageFormat.png);
    expect((info.width, info.height), (image.width, image.height));

    final decoded = await ImageFfmpeg.decodeImage(png);
    expect((decoded.width, decoded.height), (image.width, image.height));
    expect(decoded.bytes, image.bytes);
  });

  test('encodes JPEG with quality and chroma options', () async {
    final source = await _fetchFixture('test.png');
    final image = await ImageFfmpeg.decodeImage(
      source,
      maxWidth: 64,
      maxHeight: 64,
    );

    final jpeg = await ImageFfmpeg.encodeJpeg(
      image,
      quality: 90,
      chroma: JpegChroma.yuv444,
    );
    expect(jpeg.sublist(0, 3), [0xff, 0xd8, 0xff]);
    final info = await ImageFfmpeg.probeImage(jpeg);
    expect(info.format, ImageFormat.jpeg);
    expect((info.width, info.height), (image.width, image.height));
  });

  test('decodes with deterministic integer box averaging', () async {
    final source = RgbaImage(
      width: 2,
      height: 1,
      stride: 8,
      bytes: Uint8List.fromList(const [255, 0, 0, 255, 0, 0, 255, 0]),
    );
    final png = await ImageFfmpeg.encodePng(source);

    final included = await ImageFfmpeg.decodeImageBoxAverage(
      png,
      maxDimension: 1,
    );
    expect(included.bytes, [128, 0, 128, 128]);

    final opaqueOnly = await ImageFfmpeg.decodeImageBoxAverage(
      png,
      maxDimension: 1,
      alphaMode: BoxAverageAlphaMode.opaqueOnly,
    );
    expect(opaqueOnly.bytes, [255, 0, 0, 255]);
  });

  test('fills a rectangle inside the Worker', () async {
    final source = RgbaImage(
      width: 4,
      height: 3,
      stride: 16,
      bytes: Uint8List.fromList([
        for (var pixel = 0; pixel < 12; pixel++) ...[240, 241, 242, 255],
      ]),
    );
    final png = await ImageFfmpeg.encodePng(source);
    final filled = await ImageFfmpeg.fillRectangle(
      png,
      rectangle: const ImageFillRect(
        x: 1,
        y: 1,
        width: 2,
        height: 1,
        color: 0xff123456,
      ),
      output: const ImageOutput.png(),
    );
    final decoded = await ImageFfmpeg.decodeImage(filled.bytes);
    expect(decoded.bytes.sublist(20, 28), [
      0x12,
      0x34,
      0x56,
      0xff,
      0x12,
      0x34,
      0x56,
      0xff,
    ]);
  });

  test('transcodes with orientation, scale, and format change', () async {
    final source = await _fetchFixture('test_animated.webp');

    final thumbnail = await ImageFfmpeg.transcodeImage(
      source,
      output: const ImageOutput.jpeg(quality: 80),
      maxWidth: 100,
      maxHeight: 100,
    );
    expect(thumbnail.format, ImageFormat.jpeg);
    expect((thumbnail.width, thumbnail.height), (100, 100));
    expect(thumbnail.bytes.sublist(0, 3), [0xff, 0xd8, 0xff]);
  });

  test('rejects unrecognized bytes with status -6', () async {
    final garbage = Uint8List.fromList(List.generate(64, (i) => i * 7 & 0xff));
    await expectLater(
      ImageFfmpeg.decodeImage(garbage),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -6),
      ),
    );
  });

  test('serves interleaved concurrent requests by id', () async {
    final webp = await _fetchFixture('test.webp');
    final jpeg = await _fetchFixture('test.jpg');

    final results = await Future.wait([
      ImageFfmpeg.decodeImage(webp, maxWidth: 40, maxHeight: 40),
      ImageFfmpeg.decodeImage(jpeg, maxWidth: 56, maxHeight: 56),
      ImageFfmpeg.probeImage(webp).then((info) => info),
    ]);
    expect(((results[0] as RgbaImage).width), 40);
    expect(((results[1] as RgbaImage).width), 56);
    expect((results[2] as ImageInfo).format, ImageFormat.webp);
  });

  test('capabilities are shared page-wide', () async {
    expect(
      identical(await ImageFfmpeg.capabilities, await ImageFfmpeg.capabilities),
      isTrue,
    );
  });
}
