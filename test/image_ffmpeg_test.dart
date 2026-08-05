import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:test/test.dart';

void main() {
  test('loads and validates the native code asset ABI', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);

    expect(ffmpeg.capabilities.runtime, FfmpegRuntime.native);
    expect(ffmpeg.capabilities.abiVersion, 2);
    expect(ffmpeg.capabilities.buildInfo, contains('image_ffmpeg ABI 2'));
  });

  test('bundles the production FFmpeg capability', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);

    expect(ffmpeg.capabilities.canDecodeImage, isTrue);
    expect(ffmpeg.capabilities.canEncodeJpeg, isTrue);
    expect(ffmpeg.capabilities.canEncodePng, isTrue);
    expect(ffmpeg.capabilities.buildInfo, contains('Lavc63.1.100'));
  });

  test('decodes the first animated WebP frame', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final bytes = await File(
      'test/fixtures/image_formats/sources/test_animated.webp',
    ).readAsBytes();

    final info = await ffmpeg.probeImage(bytes);
    expect(info.format, ImageFormat.webp);
    expect((info.width, info.height), (800, 800));
    expect(info.hasAlpha, isTrue);

    final image = await ffmpeg.decodeImage(bytes, maxWidth: 96, maxHeight: 96);
    expect((image.width, image.height), (96, 96));
    expect(image.bytes.length, 96 * 96 * 4);
  });

  test('probes supported image bytes when FFmpeg is linked', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAACXBIWXMAAAABAAAA'
      'AQBPJcTWAAAAEElEQVR4nGP4w8AARwzIHABuWgfhm8LBSgAAAABJRU5ErkJggg==',
    );
    final image = await ffmpeg.decodeImage(png, maxWidth: 2, maxHeight: 2);
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
    final avifImage = await ffmpeg.decodeImage(avif, maxWidth: 2, maxHeight: 2);
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
    final alphaImage = await ffmpeg.decodeImage(
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
    final psdImage = await ffmpeg.decodeImage(psd);
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
    final icoImage = await ffmpeg.decodeImage(ico);
    expect((icoImage.width, icoImage.height), (4, 2));
    expect(icoImage.bytes.length, 32);
    expect(
      [for (var index = 3; index < 32; index += 4) icoImage.bytes[index]],
      [255, 255, 255, 0, 0, 255, 255, 255],
    );

    await expectLater(
      ffmpeg.decodeImage(Uint8List.fromList('not an image'.codeUnits)),
      throwsA(
        isA<FfmpegException>().having((error) => error.status, 'status', -6),
      ),
    );
  });

  test('probes metadata and performs fused transcodes', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
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
    final jpeg = await ffmpeg.encodeJpeg(
      source,
      quality: 100,
      chroma: JpegChroma.yuv444,
    );
    final decodedJpeg = await ffmpeg.decodeImage(jpeg);
    for (var orientation = 1; orientation <= 8; orientation++) {
      final oriented = _withExifOrientation(jpeg, orientation);
      final baked = await ffmpeg.transcodeImage(
        oriented,
        output: const ImageOutput.png(),
      );
      final bakedRgba = await ffmpeg.decodeImage(baked.bytes);
      final expected = _orientRgba(decodedJpeg, orientation);
      expect(
        (bakedRgba.width, bakedRgba.height),
        (expected.width, expected.height),
      );
      expect(bakedRgba.bytes, expected.bytes);
    }

    final orientedJpeg = _withExifOrientation(jpeg, 6);
    final info = await ffmpeg.probeImage(orientedJpeg);
    expect(info.format, ImageFormat.jpeg);
    expect((info.width, info.height), (3, 2));
    expect((info.displayWidth, info.displayHeight), (2, 3));
    expect(info.orientation, ImageOrientation.rotate90);
    expect(info.frameCount, 1);
    expect(info.hasAlpha, false);

    final transcoded = await ffmpeg.transcodeImage(
      orientedJpeg,
      output: const ImageOutput.png(compressionLevel: 9),
      crop: const ImageCrop(x: 0, y: 1, width: 2, height: 2),
      maxWidth: 1,
      maxHeight: 1,
    );
    expect(transcoded.format, ImageFormat.png);
    expect((transcoded.width, transcoded.height), (1, 1));
    expect(transcoded.bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);

    final png = await ffmpeg.encodePng(source);
    final passthrough = await ffmpeg.transcodeImage(
      png,
      output: const ImageOutput.png(),
      passthroughIfUnchanged: true,
    );
    expect(passthrough.bytes, png);
    expect((passthrough.width, passthrough.height), (3, 2));

    final fusedJpeg = await ffmpeg.transcodeImage(
      png,
      output: const ImageOutput.jpeg(quality: 90, chroma: JpegChroma.yuv444),
    );
    expect(fusedJpeg.format, ImageFormat.jpeg);
    expect(_jpegSampling(fusedJpeg.bytes).toSet(), hasLength(1));
  });

  test('encodes JPEG and PNG when FFmpeg is linked', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);
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

    final png = await ffmpeg.encodePng(rgba, compressionLevel: 9);
    expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final pngRoundTrip = await ffmpeg.decodeImage(png);
    expect((pngRoundTrip.width, pngRoundTrip.height), (4, 2));
    expect(pngRoundTrip.bytes, [
      ...rgba.bytes.sublist(0, 16),
      ...rgba.bytes.sublist(20, 36),
    ]);

    final jpeg = await ffmpeg.encodeJpeg(rgba, quality: 80);
    final jpeg444 = await ffmpeg.encodeJpeg(
      rgba,
      quality: 80,
      chroma: JpegChroma.yuv444,
    );
    expect(_jpegSampling(jpeg), [0x22, 0x11, 0x11]);
    expect(_jpegSampling(jpeg444).toSet(), hasLength(1));
    expect(jpeg.sublist(0, 2), [0xff, 0xd8]);
    expect(jpeg.sublist(jpeg.length - 2), [0xff, 0xd9]);
    final jpegRoundTrip = await ffmpeg.decodeImage(jpeg);
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
    final flattened = await ffmpeg.decodeImage(
      await ffmpeg.encodeJpeg(transparentRed),
    );
    expect([
      for (var index = 0; index < flattened.bytes.length; index += 4)
        ...flattened.bytes.sublist(index, index + 3),
    ], everyElement(greaterThanOrEqualTo(250)));

    final redBackground = await ffmpeg.decodeImage(
      await ffmpeg.encodeJpeg(
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

  test('validates arguments before entering the backend', () async {
    final ffmpeg = await Ffmpeg.load();
    addTearDown(ffmpeg.dispose);

    expect(() => ffmpeg.decodeImage(Uint8List(0)), throwsArgumentError);
    expect(
      () => ffmpeg.decodeImage(Uint8List(1), maxWidth: -1),
      throwsArgumentError,
    );

    final image = RgbaImage(
      width: 1,
      height: 1,
      stride: 4,
      bytes: Uint8List(4),
    );
    expect(() => ffmpeg.encodeJpeg(image, quality: 0), throwsArgumentError);
    expect(() => ffmpeg.encodeJpeg(image, quality: 101), throwsArgumentError);
    expect(
      () => ffmpeg.encodePng(image, compressionLevel: -1),
      throwsArgumentError,
    );
    expect(
      () => ffmpeg.encodePng(image, compressionLevel: 10),
      throwsArgumentError,
    );
    expect(
      () => ffmpeg.transcodeImage(
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
