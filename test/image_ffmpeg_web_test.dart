@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import 'support/browser_test_support.dart';

Future<Uint8List> _fetchFixture(String name) =>
    fetchTestAsset('fixtures/image_formats/sources/$name');

void main() {
  setUp(() => FfmpegWeb.workerUri = servedWorkerUri);
  tearDown(() => FfmpegWeb.workerUri = null);

  test('loads the Wasm worker and reports capabilities', () async {
    FfmpegWeb.workerUri = null;
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    expect(ffmpeg.capabilities.runtime, FfmpegRuntime.webAssembly);
    expect(ffmpeg.capabilities.abiVersion, 2);
    expect(ffmpeg.capabilities.canDecodeImage, isTrue);
    expect(ffmpeg.capabilities.canEncodeJpeg, isTrue);
    expect(ffmpeg.capabilities.canEncodePng, isTrue);
    expect(ffmpeg.capabilities.buildInfo, contains('Lavc63.1.100'));
  });

  test('probes and decodes the first animated WebP frame', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final bytes = await _fetchFixture('test_animated.webp');

    final info = await ffmpeg.probeImage(bytes);
    expect(info.format, ImageFormat.webp);
    expect((info.width, info.height), (800, 800));
    expect(info.hasAlpha, isTrue);

    final image = await ffmpeg.decodeImage(bytes, maxWidth: 96, maxHeight: 96);
    expect((image.width, image.height), (96, 96));
    expect(image.bytes.length, 96 * 96 * 4);
  });

  test('decode does not clobber the caller-visible input bytes', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final bytes = await _fetchFixture('test.jpg');
    final before = Uint8List.fromList(bytes);
    await ffmpeg.decodeImage(bytes, maxWidth: 32, maxHeight: 32);
    expect(bytes, before);
  });

  test('round-trips decode -> encodePng -> probe -> decode', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final jpeg = await _fetchFixture('test.jpg');

    final image = await ffmpeg.decodeImage(jpeg, maxWidth: 64, maxHeight: 64);
    final png = await ffmpeg.encodePng(image, compressionLevel: 6);
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);

    final info = await ffmpeg.probeImage(png);
    expect(info.format, ImageFormat.png);
    expect((info.width, info.height), (image.width, image.height));

    final decoded = await ffmpeg.decodeImage(png);
    expect((decoded.width, decoded.height), (image.width, image.height));
    expect(decoded.bytes, image.bytes);
  });

  test('encodes JPEG with quality and chroma options', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final source = await _fetchFixture('test.png');
    final image = await ffmpeg.decodeImage(source, maxWidth: 64, maxHeight: 64);

    final jpeg = await ffmpeg.encodeJpeg(
      image,
      quality: 90,
      chroma: JpegChroma.yuv444,
    );
    expect(jpeg.sublist(0, 3), [0xff, 0xd8, 0xff]);
    final info = await ffmpeg.probeImage(jpeg);
    expect(info.format, ImageFormat.jpeg);
    expect((info.width, info.height), (image.width, image.height));
  });

  test('transcodes with orientation, scale, and format change', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final source = await _fetchFixture('test_animated.webp');

    final thumbnail = await ffmpeg.transcodeImage(
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
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final garbage = Uint8List.fromList(List.generate(64, (i) => i * 7 & 0xff));
    await expectLater(
      ffmpeg.decodeImage(garbage),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -6),
      ),
    );
  });

  test('serves interleaved concurrent requests by id', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final webp = await _fetchFixture('test.webp');
    final jpeg = await _fetchFixture('test.jpg');

    final results = await Future.wait([
      ffmpeg.decodeImage(webp, maxWidth: 40, maxHeight: 40),
      ffmpeg.decodeImage(jpeg, maxWidth: 56, maxHeight: 56),
      ffmpeg.probeImage(webp).then((info) => info),
    ]);
    expect(((results[0] as RgbaImage).width), 40);
    expect(((results[1] as RgbaImage).width), 56);
    expect((results[2] as ImageInfo).format, ImageFormat.webp);
  });

  test('dispose terminates the worker and rejects further use', () async {
    final ffmpeg = await Ffmpeg.load();
    await ffmpeg.dispose();
    await expectLater(
      () => ffmpeg.probeImage(Uint8List.fromList([1, 2, 3])),
      throwsStateError,
    );
  });

  test('fails with a diagnosable error when the worker URL is wrong', () async {
    FfmpegWeb.workerUri = Uri.parse('packages/image_ffmpeg/web/missing.mjs');
    await expectLater(
      Ffmpeg.load(),
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
  });
}
