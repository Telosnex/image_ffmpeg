import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

void main() {
  test('capabilities are initialized lazily and shared', () async {
    expect(
      identical(await ImageFfmpeg.capabilities, await ImageFfmpeg.capabilities),
      isTrue,
    );
  });

  test('loads and validates the native code asset ABI', () async {
    final capabilities = await ImageFfmpeg.capabilities;
    expect(capabilities.runtime, FfmpegRuntime.native);
    expect(capabilities.abiVersion, 5);
    expect(capabilities.buildInfo, contains('image_ffmpeg ABI 5'));
  });

  test('package wire values are explicit and checked', () {
    expect(ImageFormat.jpeg.wireValue, 1);
    expect(ImageFormat.ico.wireValue, 10);
    expect(ImageFormat.fromWireValue(8), ImageFormat.avif);
    expect(ImageOrientation.rotate90.wireValue, 6);
    expect(
      ImageOrientation.fromWireValue(7),
      ImageOrientation.transverse,
    );
    expect(JpegChroma.yuv444.wireValue, 1);
    expect(BoxAverageAlphaMode.opaqueOnly.wireValue, 1);
    expect(() => ImageFormat.fromWireValue(99), throwsArgumentError);
    expect(() => ImageOrientation.fromWireValue(0), throwsArgumentError);
  });

  test('bundles the production FFmpeg capability', () async {
    final capabilities = await ImageFfmpeg.capabilities;
    expect(capabilities.canDecodeImage, isTrue);
    expect(capabilities.canEncodeJpeg, isTrue);
    expect(capabilities.canEncodePng, isTrue);
    expect(capabilities.buildInfo, contains('Lavc63.1.100'));
  });

  test('decodes the first animated WebP frame', () async {
    final bytes = await File(
      'test/fixtures/image_formats/sources/test_animated.webp',
    ).readAsBytes();

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

  test('probes supported image bytes when FFmpeg is linked', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAACXBIWXMAAAABAAAA'
      'AQBPJcTWAAAAEElEQVR4nGP4w8AARwzIHABuWgfhm8LBSgAAAABJRU5ErkJggg==',
    );
    final image = await ImageFfmpeg.decodeImage(png, maxWidth: 2, maxHeight: 2);
    expect((image.width, image.height), (2, 1));
    expect(image.bytes.length, 8);

    final avif = base64Decode(
      'AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAAD5bWV0YQAAAAAAAAAv'
      'aGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAFBpY3R1cmVIYW5kbGVyAAAAAA5w'
      'aXRtAAAAAAABAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAASEAAAAbAAAAKGlpbmYA'
      'AAAAAAEAAAAaaW5mZQIAAAAAAQAAYXYwMUNvbG9yAAAAAGppcHJwAAAAS2lwY28A'
      'AAAUaXNwZQAAAAAAAAAEAAAAAgAAABBwaXhpAAAAAAMICAgAAAAMYXYxQ4EADAAA'
      'AAATY29scm5jbHgAAgACAAIAAAAAF2lwbWEAAAAAAAAAAQABBAECgwQAAAAjbWRh'
      'dAoFGAQ7YBAyEhgAAABQAABAA1Lt5xf080WmIA==',
    );
    final avifImage = await ImageFfmpeg.decodeImage(
      avif,
      maxWidth: 2,
      maxHeight: 2,
    );
    expect((avifImage.width, avifImage.height), (2, 1));
    expect(avifImage.bytes.length, 8);

    final alphaAvif = base64Decode(
      'AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUEAAAGGbWV0YQAAAAAAAAAh'
      'aGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAAAAAAAOcGl0bQAAAAAAAQAAACxp'
      'bG9jAAAAAEQAAAIAAQAAAAEAAAHLAAAANQACAAAAAQAAAa4AAAAdAAAAQmlpbmYA'
      'AAAAAAIAAAAaaW5mZQIAAAAAAQAAYXYwMUNvbG9yAAAAABppbmZlAgAAAAACAABh'
      'djAxQWxwaGEAAAAAGmlyZWYAAAAAAAAADmF1eGwAAgABAAEAAADDaXBycAAAAJ1p'
      'cGNvAAAAFGlzcGUAAAAAAAAAIAAAABgAAAAQcGl4aQAAAAADCAgIAAAADGF2MUOB'
      'IAAAAAAAE2NvbHJuY2x4AAEAAgAGgAAAAA5waXhpAAAAAAEIAAAADGF2MUOBABwA'
      'AAAAOGF1eEMAAAAAdXJuOm1wZWc6bXBlZ0I6Y2ljcDpzeXN0ZW1zOmF1eGlsaWFy'
      'eTphbHBoYQAAAAAeaXBtYQAAAAAAAAACAAEEAQKDBAACBAEFhgcAAABabWRhdBIA'
      'CgUYET92FTISFkAYYUC13uQdZggHNJ0zABRAEgAKBTgRP3YJMioWQAYYYYUAvKyX'
      'N6bT7I/szENB5h6dvRcbHyUW2xJMCWIeAeBeCdeJz4A=',
    );
    final alphaImage = await ImageFfmpeg.decodeImage(
      alphaAvif,
      maxWidth: 16,
      maxHeight: 16,
    );
    expect((alphaImage.width, alphaImage.height), (16, 12));
    final middleRow = alphaImage.height ~/ 2;
    final leftAlpha =
        alphaImage.bytes[(middleRow * alphaImage.width + 2) * 4 + 3];
    final rightAlpha =
        alphaImage.bytes[(middleRow * alphaImage.width + 14) * 4 + 3];
    expect(leftAlpha, closeTo(128, 2));
    expect(rightAlpha, 255);

    final psd = base64Decode(
      'OEJQUwABAAAAAAAAAAMAAAACAAAABAAQAAMAAAAAAAAAAAAAAIAAAAB4AAEAAAAA'
      'AAAAAAAAAAIAAAAEAAMAAAAAABIAAQAAABIAAgAAABI4QklNbm9ybf8AAQAAAAAM'
      'AAAAAAAAAAACTDEAAAD/////////////////////AAAAAAAAAAAAAAAAAAAAAAAA'
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/////////////////////wAAAAAAAAAA'
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
    final psdImage = await ImageFfmpeg.decodeImage(psd);
    expect((psdImage.width, psdImage.height), (4, 2));
    expect(psdImage.bytes.length, 32);
    expect(psdImage.bytes.sublist(0, 4), [255, 0, 0, 255]);

    final ico = base64Decode(
      'AAABAAIAAQEAAAEAIABaAAAAJgAAAAQCAAABABgASAAAAIAAAACJUE5HDQoaCgAA'
      'AA1JSERSAAAAAQAAAAEIAgAAAJB3U94AAAAJcEhZcwAAAAEAAAABAE8lxNYAAAAM'
      'SURBVHicY2Bg+A8AAQMBAAiJwuwAAAAASUVORK5CYIIoAAAABAAAAAQAAAABABgA'
      'AAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAP8AAP8AAP8AAP8AAAD/AAD/AAD/AAD/'
      'gAAAABAAAAA=',
    );
    final icoImage = await ImageFfmpeg.decodeImage(ico);
    expect((icoImage.width, icoImage.height), (4, 2));
    expect(icoImage.bytes.length, 32);
    expect(
      [for (var index = 3; index < 32; index += 4) icoImage.bytes[index]],
      [255, 255, 255, 0, 0, 255, 255, 255],
    );

    await expectLater(
      ImageFfmpeg.decodeImage(Uint8List.fromList('not an image'.codeUnits)),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -6),
      ),
    );
  });

  test('probes metadata and performs fused transcodes', () async {
    final source = RgbaImage(
      width: 3,
      height: 2,
      stride: 12,
      bytes: Uint8List.fromList(const [
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        255,
        255,
        0,
        255,
        0,
        255,
        255,
        255,
        255,
        0,
        255,
        255,
      ]),
    );
    final jpeg = await ImageFfmpeg.encodeJpeg(
      source,
      quality: 100,
      chroma: JpegChroma.yuv444,
    );
    final decodedJpeg = await ImageFfmpeg.decodeImage(jpeg);
    for (var orientation = 1; orientation <= 8; orientation++) {
      final oriented = _withExifOrientation(jpeg, orientation);
      final baked = await ImageFfmpeg.transcodeImage(
        oriented,
        output: const ImageOutput.png(),
      );
      final bakedRgba = await ImageFfmpeg.decodeImage(baked.bytes);
      final expected = _orientRgba(decodedJpeg, orientation);
      expect(
        (bakedRgba.width, bakedRgba.height),
        (expected.width, expected.height),
      );
      expect(bakedRgba.bytes, expected.bytes);
    }

    final orientedJpeg = _withExifOrientation(jpeg, 6);
    final info = await ImageFfmpeg.probeImage(orientedJpeg);
    expect(info.format, ImageFormat.jpeg);
    expect((info.width, info.height), (3, 2));
    expect((info.displayWidth, info.displayHeight), (2, 3));
    expect(info.orientation, ImageOrientation.rotate90);
    expect(info.frameCount, 1);
    expect(info.hasAlpha, false);

    final transcoded = await ImageFfmpeg.transcodeImage(
      orientedJpeg,
      output: const ImageOutput.png(compressionLevel: 9),
      crop: const ImageCrop(x: 0, y: 1, width: 2, height: 2),
      maxWidth: 1,
      maxHeight: 1,
    );
    expect(transcoded.format, ImageFormat.png);
    expect((transcoded.width, transcoded.height), (1, 1));
    expect(transcoded.bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);

    final png = await ImageFfmpeg.encodePng(source);
    final passthrough = await ImageFfmpeg.transcodeImage(
      png,
      output: const ImageOutput.png(),
      passthroughIfUnchanged: true,
    );
    expect(passthrough.bytes, png);
    expect((passthrough.width, passthrough.height), (3, 2));

    final fusedJpeg = await ImageFfmpeg.transcodeImage(
      png,
      output: const ImageOutput.jpeg(quality: 90, chroma: JpegChroma.yuv444),
    );
    expect(fusedJpeg.format, ImageFormat.jpeg);
    expect(_jpegSampling(fusedJpeg.bytes).toSet(), hasLength(1));
  });

  test('encodes JPEG and PNG when FFmpeg is linked', () async {
    final rgba = RgbaImage(
      width: 4,
      height: 2,
      stride: 20,
      bytes: Uint8List.fromList([
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        128,
        0,
        0,
        255,
        0,
        255,
        255,
        255,
        255,
        1,
        2,
        3,
        4,
        0,
        0,
        0,
        255,
        255,
        255,
        0,
        64,
        0,
        255,
        255,
        192,
        255,
        0,
        255,
        255,
        5,
        6,
        7,
        8,
      ]),
    );

    final png = await ImageFfmpeg.encodePng(rgba, compressionLevel: 9);
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final pngRoundTrip = await ImageFfmpeg.decodeImage(png);
    expect((pngRoundTrip.width, pngRoundTrip.height), (4, 2));
    expect(pngRoundTrip.bytes, [
      ...rgba.bytes.sublist(0, 16),
      ...rgba.bytes.sublist(20, 36),
    ]);

    final jpeg = await ImageFfmpeg.encodeJpeg(rgba, quality: 80);
    final jpeg444 = await ImageFfmpeg.encodeJpeg(
      rgba,
      quality: 80,
      chroma: JpegChroma.yuv444,
    );
    expect(_jpegSampling(jpeg), [0x22, 0x11, 0x11]);
    expect(_jpegSampling(jpeg444).toSet(), hasLength(1));
    expect(jpeg.sublist(0, 2), [0xff, 0xd8]);
    expect(jpeg.sublist(jpeg.length - 2), [0xff, 0xd9]);
    final jpegRoundTrip = await ImageFfmpeg.decodeImage(jpeg);
    expect((jpegRoundTrip.width, jpegRoundTrip.height), (4, 2));
    expect([
      for (var index = 3; index < jpegRoundTrip.bytes.length; index += 4)
        jpegRoundTrip.bytes[index],
    ], everyElement(255));

    final transparentRed = RgbaImage(
      width: 16,
      height: 16,
      stride: 64,
      bytes: Uint8List.fromList([
        for (var pixel = 0; pixel < 16 * 16; pixel++) ...[255, 0, 0, 0],
      ]),
    );
    final flattened = await ImageFfmpeg.decodeImage(
      await ImageFfmpeg.encodeJpeg(transparentRed),
    );
    expect([
      for (var index = 0; index < flattened.bytes.length; index += 4)
        ...flattened.bytes.sublist(index, index + 3),
    ], everyElement(greaterThanOrEqualTo(250)));

    final redBackground = await ImageFfmpeg.decodeImage(
      await ImageFfmpeg.encodeJpeg(
        transparentRed,
        chroma: JpegChroma.yuv444,
        backgroundColor: 0xffff0000,
      ),
    );
    for (var index = 0; index < redBackground.bytes.length; index += 4) {
      expect(redBackground.bytes[index], greaterThanOrEqualTo(250));
      expect(redBackground.bytes[index + 1], lessThanOrEqualTo(5));
      expect(redBackground.bytes[index + 2], lessThanOrEqualTo(5));
    }
  });

  test('fills a rectangle without crossing an RGBA buffer into Dart', () async {
    final source = RgbaImage(
      width: 6,
      height: 4,
      stride: 24,
      bytes: Uint8List.fromList([
        for (var pixel = 0; pixel < 24; pixel++) ...[200, 210, 220, 255],
      ]),
    );
    final png = await ImageFfmpeg.encodePng(source);
    final filled = await ImageFfmpeg.fillRectangle(
      png,
      rectangle: const ImageFillRect(
        x: 2,
        y: 1,
        width: 3,
        height: 2,
        color: 0xff112233,
      ),
      output: const ImageOutput.png(),
    );
    expect(
      (filled.width, filled.height, filled.format),
      (6, 4, ImageFormat.png),
    );

    final decoded = await ImageFfmpeg.decodeImage(filled.bytes);
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final offset = y * decoded.stride + x * 4;
        expect(
          decoded.bytes.sublist(offset, offset + 4),
          x >= 2 && x < 5 && y >= 1 && y < 3
              ? [0x11, 0x22, 0x33, 0xff]
              : [200, 210, 220, 255],
          reason: 'pixel ($x, $y)',
        );
      }
    }

    await expectLater(
      ImageFfmpeg.fillRectangle(
        png,
        rectangle: const ImageFillRect(
          x: 5,
          y: 0,
          width: 2,
          height: 1,
          color: 0xff000000,
        ),
        output: const ImageOutput.jpeg(),
      ),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -1),
      ),
    );
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
    expect((included.width, included.height, included.stride), (1, 1, 4));
    expect(included.bytes, [128, 0, 128, 128]);

    final opaqueOnly = await ImageFfmpeg.decodeImageBoxAverage(
      png,
      maxDimension: 1,
      alphaMode: BoxAverageAlphaMode.opaqueOnly,
    );
    expect(opaqueOnly.bytes, [255, 0, 0, 255]);
  });

  test('box averaging has fixed cell boundaries and rounding', () async {
    const width = 7;
    const height = 5;
    final source = RgbaImage(
      width: width,
      height: height,
      stride: width * 4,
      bytes: Uint8List.fromList([
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) ...[
            x * 31 + y,
            y * 47 + x,
            x * 17 + y * 13,
            (x + y).isEven ? 255 : 127,
          ],
      ]),
    );
    final png = await ImageFfmpeg.encodePng(source);
    final decoded = await ImageFfmpeg.decodeImage(png);

    for (final alphaMode in BoxAverageAlphaMode.values) {
      final actual = await ImageFfmpeg.decodeImageBoxAverage(
        png,
        maxDimension: 3,
        alphaMode: alphaMode,
      );
      final expected = _referenceBoxAverage(
        decoded,
        maxDimension: 3,
        alphaMode: alphaMode,
      );
      expect((actual.width, actual.height), (3, 2));
      expect(actual.bytes, expected.bytes, reason: alphaMode.name);
    }
  });

  test('streamed box averaging is exact across strip boundaries', () async {
    const width = 91;
    const height = 137;
    final source = RgbaImage(
      width: width,
      height: height,
      stride: width * 4,
      bytes: Uint8List.fromList([
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++) ...[
            (x * 17 + y * 3) & 0xff,
            (x * 5 + y * 29) & 0xff,
            (x * 31 + y * 11) & 0xff,
            (x + y) % 7 == 0 ? 127 : 255,
          ],
      ]),
    );
    final png = await ImageFfmpeg.encodePng(source);
    final jpeg420 = await ImageFfmpeg.encodeJpeg(source, quality: 100);
    final jpeg444 = await ImageFfmpeg.encodeJpeg(
      source,
      quality: 100,
      chroma: JpegChroma.yuv444,
    );

    for (final (:format, :encoded) in [
      (format: 'png', encoded: png),
      (format: 'jpeg420', encoded: jpeg420),
      (format: 'jpeg444', encoded: jpeg444),
    ]) {
      final decoded = await ImageFfmpeg.decodeImage(encoded);
      for (final maxDimension in [43, 200]) {
        for (final alphaMode in BoxAverageAlphaMode.values) {
          final actual = await ImageFfmpeg.decodeImageBoxAverage(
            encoded,
            maxDimension: maxDimension,
            alphaMode: alphaMode,
          );
          final expected = _referenceBoxAverage(
            decoded,
            maxDimension: maxDimension,
            alphaMode: alphaMode,
          );
          expect(
            (actual.width, actual.height, actual.stride),
            (expected.width, expected.height, expected.stride),
          );
          expect(
            actual.bytes,
            expected.bytes,
            reason:
                'format=$format, maxDimension=$maxDimension, '
                'alphaMode=${alphaMode.name}',
          );
        }
      }
    }
  });

  test('streamed box averaging matches every supported fixture', () async {
    final sources =
        Directory(
            'test/fixtures/image_formats/sources',
          ).listSync().whereType<File>().toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final source in sources) {
      final encoded = await source.readAsBytes();
      final decoded = await ImageFfmpeg.decodeImage(encoded);
      for (final alphaMode in BoxAverageAlphaMode.values) {
        final actual = await ImageFfmpeg.decodeImageBoxAverage(
          encoded,
          maxDimension: 31,
          alphaMode: alphaMode,
        );
        final expected = _referenceBoxAverage(
          decoded,
          maxDimension: 31,
          alphaMode: alphaMode,
        );
        expect(
          actual.bytes,
          expected.bytes,
          reason: '${source.path}, alphaMode=${alphaMode.name}',
        );
      }
    }
  });

  test('validates arguments before entering the backend', () async {
    expect(() => ImageFfmpeg.decodeImage(Uint8List(0)), throwsArgumentError);
    expect(
      () => ImageFfmpeg.decodeImage(Uint8List(1), maxWidth: -1),
      throwsArgumentError,
    );
    expect(
      () => ImageFfmpeg.decodeImageBoxAverage(Uint8List(1), maxDimension: 0),
      throwsArgumentError,
    );

    final image = RgbaImage(
      width: 1,
      height: 1,
      stride: 4,
      bytes: Uint8List(4),
    );
    expect(
      () => ImageFfmpeg.encodeJpeg(image, quality: 0),
      throwsArgumentError,
    );
    expect(
      () => ImageFfmpeg.encodeJpeg(image, quality: 101),
      throwsArgumentError,
    );
    expect(
      () => ImageFfmpeg.encodePng(image, compressionLevel: -1),
      throwsArgumentError,
    );
    expect(
      () => ImageFfmpeg.encodePng(image, compressionLevel: 10),
      throwsArgumentError,
    );
    expect(
      () => ImageFfmpeg.transcodeImage(
        Uint8List(1),
        output: const ImageOutput.jpeg(quality: 0),
      ),
      throwsArgumentError,
    );
  });
}

Uint8List _withExifOrientation(Uint8List jpeg, int orientation) {
  // APP1 payload: Exif header followed by a big-endian TIFF IFD0 containing
  // only tag 0x0112 (Orientation).
  final app1 = Uint8List.fromList([
    0xff,
    0xe1,
    0x00,
    0x22,
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    0x4d,
    0x4d,
    0x00,
    0x2a,
    0x00,
    0x00,
    0x00,
    0x08,
    0x00,
    0x01,
    0x01,
    0x12,
    0x00,
    0x03,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    orientation,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  var insertionOffset = 2;
  if (jpeg.length >= 6 && jpeg[2] == 0xff && jpeg[3] == 0xe0) {
    insertionOffset = 4 + (jpeg[4] << 8 | jpeg[5]);
  }
  return Uint8List.fromList([
    ...jpeg.sublist(0, insertionOffset),
    ...app1,
    ...jpeg.sublist(insertionOffset),
  ]);
}

RgbaImage _orientRgba(RgbaImage source, int orientation) {
  final swapsAxes = orientation >= 5;
  final width = swapsAxes ? source.height : source.width;
  final height = swapsAxes ? source.width : source.height;
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (sourceX, sourceY) = switch (orientation) {
        1 => (x, y),
        2 => (source.width - 1 - x, y),
        3 => (source.width - 1 - x, source.height - 1 - y),
        4 => (x, source.height - 1 - y),
        5 => (y, x),
        6 => (y, source.height - 1 - x),
        7 => (source.width - 1 - y, source.height - 1 - x),
        8 => (source.width - 1 - y, x),
        _ => throw ArgumentError.value(orientation),
      };
      final sourceOffset = sourceY * source.stride + sourceX * 4;
      final destinationOffset = (y * width + x) * 4;
      bytes.setRange(
        destinationOffset,
        destinationOffset + 4,
        source.bytes,
        sourceOffset,
      );
    }
  }
  return RgbaImage(
    width: width,
    height: height,
    stride: width * 4,
    bytes: bytes,
  );
}

List<int> _jpegSampling(Uint8List jpeg) {
  for (var index = 2; index + 18 < jpeg.length; index++) {
    if (jpeg[index] == 0xff && jpeg[index + 1] == 0xc0) {
      return [jpeg[index + 11], jpeg[index + 14], jpeg[index + 17]];
    }
  }
  throw StateError('JPEG has no baseline SOF marker');
}

RgbaImage _referenceBoxAverage(
  RgbaImage source, {
  required int maxDimension,
  required BoxAverageAlphaMode alphaMode,
}) {
  var width = source.width;
  var height = source.height;
  if (width > maxDimension || height > maxDimension) {
    (width, height) = source.width >= source.height
        ? (maxDimension, source.height * maxDimension ~/ source.width)
        : (source.width * maxDimension ~/ source.height, maxDimension);
  }
  final sums = List.filled(width * height * 4, 0);
  final counts = List.filled(width * height, 0);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final sourceOffset = y * source.stride + x * 4;
      if (alphaMode == BoxAverageAlphaMode.opaqueOnly &&
          source.bytes[sourceOffset + 3] != 255) {
        continue;
      }
      final cell =
          (y * height ~/ source.height) * width + x * width ~/ source.width;
      for (var channel = 0; channel < 4; channel++) {
        sums[cell * 4 + channel] += source.bytes[sourceOffset + channel];
      }
      counts[cell]++;
    }
  }

  final bytes = Uint8List(width * height * 4);
  for (var cell = 0; cell < counts.length; cell++) {
    final count = counts[cell];
    if (count == 0) continue;
    final half = count >> 1;
    for (var channel = 0; channel < 4; channel++) {
      bytes[cell * 4 + channel] = (sums[cell * 4 + channel] + half) ~/ count;
    }
    if (alphaMode == BoxAverageAlphaMode.opaqueOnly) {
      bytes[cell * 4 + 3] = 255;
    }
  }
  return RgbaImage(
    width: width,
    height: height,
    stride: width * 4,
    bytes: bytes,
  );
}
