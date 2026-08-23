import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

import '../tool/support/synthetic_operation_corpus.dart';
import 'support/synthetic_platform_stub.dart'
    if (dart.library.js_interop) 'support/synthetic_platform_web.dart';

void main() {
  configureSyntheticTestPlatform();

  late SyntheticSource landscape;
  late SyntheticSource portrait;

  setUpAll(() async {
    final capabilities = await ImageFfmpeg.capabilities;
    if (!capabilities.canDecodeImage) {
      throw StateError('Synthetic operation corpus requires FFmpeg.');
    }
    landscape = buildSyntheticSource(width: 17, height: 13, seed: 0x170d);
    portrait = buildSyntheticSource(width: 11, height: 19, seed: 0x0b13);
  });

  test('v1 operation manifest is stable and unique', () {
    expect(syntheticOperationCorpusVersion, 1);
    expect(syntheticOperationIds, hasLength(21));
    expect(syntheticOperationIds.toSet(), hasLength(21));
    expect(syntheticOperationIds, everyElement(startsWith('v1/')));
  });

  test('independent prime-dimension PNGs decode byte-exactly', () async {
    for (final entry in const [
      (id: 'v1/decode-prime-17x13', width: 17, height: 13, seed: 0x170d),
      (id: 'v1/decode-prime-19x11', width: 19, height: 11, seed: 0x130b),
      (id: 'v1/decode-prime-23x17', width: 23, height: 17, seed: 0x1711),
    ]) {
      final source = buildSyntheticSource(
        width: entry.width,
        height: entry.height,
        seed: entry.seed,
      );
      final decoded = await ImageFfmpeg.decodeImage(source.png);
      _expectRgba(decoded, source.rgba, entry.width, entry.height, entry.id);
    }
  });

  test('RGBA encoders ignore poisoned row padding', () async {
    for (final entry in const [
      (id: 'v1/encode-padding-7', padding: 7),
      (id: 'v1/encode-padding-13', padding: 13),
      (id: 'v1/encode-padding-29', padding: 29),
    ]) {
      final png = await ImageFfmpeg.encodePng(
        paddedRgba(landscape, entry.padding),
      );
      final decoded = await ImageFfmpeg.decodeImage(png);
      _expectRgba(
        decoded,
        landscape.rgba,
        landscape.width,
        landscape.height,
        entry.id,
      );
    }
  });

  test('lossless crops use exact edge and one-pixel coordinates', () async {
    for (final entry in [
      (
        id: 'v1/crop-top-left',
        crop: const ImageCrop(x: 0, y: 0, width: 7, height: 5),
      ),
      (
        id: 'v1/crop-bottom-right',
        crop: const ImageCrop(x: 10, y: 8, width: 7, height: 5),
      ),
      (
        id: 'v1/crop-one-pixel',
        crop: const ImageCrop(x: 16, y: 12, width: 1, height: 1),
      ),
      (
        id: 'v1/crop-prime-interior',
        crop: const ImageCrop(x: 2, y: 3, width: 11, height: 7),
      ),
    ]) {
      final encoded = await ImageFfmpeg.transcodeImage(
        landscape.png,
        output: const ImageOutput.png(compressionLevel: 6),
        applyOrientation: false,
        crop: entry.crop,
      );
      final decoded = await ImageFfmpeg.decodeImage(encoded.bytes);
      _expectRgba(
        decoded,
        cropRgba(landscape, entry.crop),
        entry.crop.width,
        entry.crop.height,
        entry.id,
      );
    }
  });

  test('lossless fills preserve every pixel outside the rectangle', () async {
    for (final entry in [
      (
        id: 'v1/fill-top-edge',
        fill: const ImageFillRect(
          x: 0,
          y: 0,
          width: 17,
          height: 2,
          color: 0xffff0080,
        ),
      ),
      (
        id: 'v1/fill-bottom-right',
        fill: const ImageFillRect(
          x: 12,
          y: 9,
          width: 5,
          height: 4,
          color: 0xff204060,
        ),
      ),
      (
        id: 'v1/fill-one-pixel',
        fill: const ImageFillRect(
          x: 8,
          y: 6,
          width: 1,
          height: 1,
          color: 0xff010203,
        ),
      ),
      (
        id: 'v1/fill-transparent-hidden-rgb',
        fill: const ImageFillRect(
          x: 3,
          y: 4,
          width: 7,
          height: 5,
          color: 0x00123456,
        ),
      ),
    ]) {
      final encoded = await ImageFfmpeg.fillRectangle(
        landscape.png,
        rectangle: entry.fill,
        output: const ImageOutput.png(compressionLevel: 6),
      );
      final decoded = await ImageFfmpeg.decodeImage(encoded.bytes);
      _expectRgba(
        decoded,
        fillRgba(landscape, entry.fill),
        landscape.width,
        landscape.height,
        entry.id,
      );
    }
  });

  test('box averaging matches the pure-Dart integer oracle', () async {
    for (final entry in [
      (
        id: 'v1/box-include-landscape',
        source: landscape,
        mode: BoxAverageAlphaMode.include,
      ),
      (
        id: 'v1/box-include-portrait',
        source: portrait,
        mode: BoxAverageAlphaMode.include,
      ),
      (
        id: 'v1/box-opaque-landscape',
        source: landscape,
        mode: BoxAverageAlphaMode.opaqueOnly,
      ),
      (
        id: 'v1/box-opaque-portrait',
        source: portrait,
        mode: BoxAverageAlphaMode.opaqueOnly,
      ),
    ]) {
      final actual = await ImageFfmpeg.decodeImageBoxAverage(
        entry.source.png,
        maxDimension: 7,
        alphaMode: entry.mode,
      );
      final expected = boxAverage(entry.source, 7, entry.mode);
      _expectRgba(
        actual,
        expected.bytes,
        expected.width,
        expected.height,
        entry.id,
      );
    }
  });

  test('unchanged PNG passthrough is byte-identical', () async {
    final result = await ImageFfmpeg.transcodeImage(
      landscape.png,
      output: const ImageOutput.png(),
      passthroughIfUnchanged: true,
    );
    expect(result.bytes, landscape.png, reason: 'v1/passthrough-png');
    expect((result.width, result.height), (17, 13));
  });

  test('compound crop-fit rounding is deterministic', () async {
    Future<EncodedImage> run() => ImageFfmpeg.transcodeImage(
      landscape.png,
      output: const ImageOutput.png(compressionLevel: 6),
      applyOrientation: false,
      crop: const ImageCrop(x: 1, y: 1, width: 15, height: 11),
      maxWidth: 11,
      maxHeight: 7,
    );

    final first = await run();
    final second = await run();
    expect(
      (first.width, first.height),
      (9, 7),
      reason: 'v1/crop-fit-prime-rounding',
    );
    expect(first.bytes, second.bytes, reason: 'v1/crop-fit-prime-rounding');
    final decoded = await ImageFfmpeg.decodeImage(first.bytes);
    expect((decoded.width, decoded.height), (9, 7));
  });

  test(
    'transparent JPEG pixels composite onto the requested background',
    () async {
      const width = 8;
      const height = 8;
      final bytes = Uint8List(width * height * 4);
      for (var offset = 0; offset < bytes.length; offset += 4) {
        bytes[offset] = 240;
        bytes[offset + 1] = 3;
        bytes[offset + 2] = 190;
        bytes[offset + 3] = 0;
      }
      final jpeg = await ImageFfmpeg.encodeJpeg(
        RgbaImage(
          width: width,
          height: height,
          stride: width * 4,
          bytes: bytes,
        ),
        quality: 100,
        chroma: JpegChroma.yuv444,
        backgroundColor: 0xff102030,
      );
      final decoded = await ImageFfmpeg.decodeImage(jpeg);
      for (var offset = 0; offset < decoded.bytes.length; offset += 4) {
        expect(decoded.bytes[offset], closeTo(0x10, 3));
        expect(decoded.bytes[offset + 1], closeTo(0x20, 3));
        expect(decoded.bytes[offset + 2], closeTo(0x30, 3));
        expect(decoded.bytes[offset + 3], 255);
      }
    },
  );

  test('curated malformed classes retain precise statuses', () async {
    final random = Uint8List.fromList(const [1, 2, 3]);
    final malformedIco = Uint8List.fromList(const [0, 0, 1, 0, 1, 0]);
    final truncatedPng = Uint8List.fromList(const [
      0x89,
      0x50,
      0x4e,
      0x47,
      13,
      10,
      26,
      10,
    ]);
    await _expectStatus(ImageFfmpeg.probeImage(random), -6, 'random/probe');
    await _expectStatus(ImageFfmpeg.decodeImage(random), -6, 'random/decode');
    await _expectStatus(
      ImageFfmpeg.probeImage(malformedIco),
      -3,
      'malformed-ico/probe',
    );
    await _expectStatus(
      ImageFfmpeg.decodeImage(malformedIco),
      -3,
      'malformed-ico/decode',
    );
    await _expectStatus(
      ImageFfmpeg.probeImage(truncatedPng),
      -5,
      'truncated-png/probe',
    );
    await _expectStatus(
      ImageFfmpeg.decodeImage(truncatedPng),
      -3,
      'truncated-png/decode',
    );
  });
}

Future<void> _expectStatus(Future<Object?> operation, int status, String id) =>
    expectLater(
      operation,
      throwsA(
        isA<FfmpegException>().having(
          (error) => error.status,
          'status ($id)',
          status,
        ),
      ),
    );

void _expectRgba(
  RgbaImage actual,
  Uint8List expected,
  int width,
  int height,
  String id,
) {
  expect((actual.width, actual.height), (width, height), reason: id);
  expect(actual.stride, width * 4, reason: id);
  expect(actual.bytes, expected, reason: id);
}
