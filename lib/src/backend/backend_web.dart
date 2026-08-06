import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../models.dart';
import '../web_config.dart';
import 'backend.dart';

/// Must match `IMAGE_FFMPEG_ABI_VERSION` in `src/image_ffmpeg.h` and
/// `ABI_VERSION` in `lib/web/image_ffmpeg_loader.mjs`.
const _abiVersion = 4;

/// Must match `IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888` in `src/image_ffmpeg.h`.
const _pixelFormatRgba8888 = 1;

/// Flutter web bundles the pubspec-declared package assets at this app-origin
/// path; it is resolved against the document base URI so `<base href>` works.
const _flutterAssetWorkerUrl =
    'assets/packages/image_ffmpeg/web/image_ffmpeg_worker.mjs';

/// Browser implementation of the shared backend contract.
///
/// All FFmpeg work happens inside `lib/web/image_ffmpeg_worker.mjs`, a module
/// Worker wrapping the same C ABI that native platforms call through
/// `dart:ffi`. Requests carry transferred `ArrayBuffer`s in both directions so
/// large images cross threads without structured-clone copies.
Future<FfmpegBackend> loadBackend() async {
  final configuredUri =
      ImageFfmpegWeb.workerUri ?? Uri.parse(_flutterAssetWorkerUrl);
  final workerUrl = Uri.parse(
    _documentBaseUri,
  ).resolveUri(configuredUri).toString();
  final backend = _WebBackend(workerUrl);
  try {
    final result = _CapabilitiesResult.wrap(
      await backend._request(
        (id) => _WorkerRequest(id: id, operation: 'capabilities'),
      ),
    );
    if (result.abiVersion != _abiVersion) {
      throw StateError(
        'image_ffmpeg ABI mismatch: Dart expects $_abiVersion, Wasm module '
        'provides ${result.abiVersion}',
      );
    }
    backend._capabilities = FfmpegCapabilities(
      runtime: FfmpegRuntime.webAssembly,
      abiVersion: result.abiVersion,
      buildInfo: result.buildInfo,
      canDecodeImage: result.hasFfmpeg,
    );
    return backend;
  } on Object {
    backend._terminate();
    rethrow;
  }
}

final class _WebBackend implements FfmpegBackend {
  _WebBackend(this._workerUrl)
    : _worker = _Worker(_workerUrl, _WorkerOptions(type: 'module')) {
    _worker.onmessage = _handleMessage.toJS;
    _worker.onerror = _handleError.toJS;
  }

  final String _workerUrl;
  final _Worker _worker;
  final _pending = <int, Completer<JSObject>>{};
  int _nextRequestId = 0;
  bool _terminated = false;
  late final FfmpegCapabilities _capabilities;

  @override
  FfmpegCapabilities get capabilities => _capabilities;

  @override
  Future<ImageInfo> probeImage(Uint8List encoded) async {
    final buffer = _transferableBuffer(encoded);
    final result = _ProbeResult.wrap(
      await _request(
        (id) =>
            _WorkerRequest(id: id, operation: 'probeImage', encoded: buffer),
        transfer: buffer,
      ),
    );
    return ImageInfo(
      format: ImageFormat.values[result.format],
      width: result.width,
      height: result.height,
      displayWidth: result.displayWidth,
      displayHeight: result.displayHeight,
      orientation: ImageOrientation.values[result.orientation - 1],
      frameCount: result.frameCount,
      hasAlpha: switch (result.hasAlpha) {
        0 => false,
        1 => true,
        _ => null,
      },
    );
  }

  @override
  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  }) async {
    final buffer = _transferableBuffer(encoded);
    final result = _DecodeResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'decodeImage',
          encoded: buffer,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        transfer: buffer,
      ),
    );
    return _rgbaImageFromResult(result);
  }

  @override
  Future<RgbaImage> decodeImageBoxAverage(
    Uint8List encoded, {
    required int maxDimension,
    required BoxAverageAlphaMode alphaMode,
  }) async {
    final buffer = _transferableBuffer(encoded);
    final result = _DecodeResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'decodeImageBoxAverage',
          encoded: buffer,
          maxDimension: maxDimension,
          alphaMode: alphaMode.index,
        ),
        transfer: buffer,
      ),
    );
    return _rgbaImageFromResult(result);
  }

  @override
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  }) async {
    final buffer = _transferableBuffer(image.bytes);
    final result = _EncodeResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'encodeJpeg',
          bytes: buffer,
          width: image.width,
          height: image.height,
          stride: image.stride,
          quality: quality,
          chroma: chroma.index,
          backgroundColor: backgroundColor,
        ),
        transfer: buffer,
      ),
    );
    return result.bytes.toDart;
  }

  @override
  Future<Uint8List> encodePng(
    RgbaImage image, {
    required int compressionLevel,
  }) async {
    final buffer = _transferableBuffer(image.bytes);
    final result = _EncodeResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'encodePng',
          bytes: buffer,
          width: image.width,
          height: image.height,
          stride: image.stride,
          compressionLevel: compressionLevel,
        ),
        transfer: buffer,
      ),
    );
    return result.bytes.toDart;
  }

  @override
  Future<EncodedImage> transcodeImage(
    Uint8List encoded, {
    required ImageOutput output,
    required int maxWidth,
    required int maxHeight,
    required bool applyOrientation,
    required ImageCrop? crop,
    required ImageFillRect? fill,
    required bool passthroughIfUnchanged,
  }) async {
    final buffer = _transferableBuffer(encoded);
    final result = _TranscodeResult.wrap(
      await _request(
        (id) => _WorkerRequest(
          id: id,
          operation: 'transcodeImage',
          encoded: buffer,
          options: _TranscodeOptions(
            outputFormat: output.format.index,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            applyOrientation: applyOrientation,
            cropX: crop?.x ?? 0,
            cropY: crop?.y ?? 0,
            cropWidth: crop?.width ?? 0,
            cropHeight: crop?.height ?? 0,
            fillX: fill?.x ?? 0,
            fillY: fill?.y ?? 0,
            fillWidth: fill?.width ?? 0,
            fillHeight: fill?.height ?? 0,
            fillColor: fill?.color ?? 0,
            jpegQuality: switch (output) {
              JpegImageOutput() => output.quality,
              PngImageOutput() => 80,
            },
            jpegChroma: switch (output) {
              JpegImageOutput() => output.chroma.index,
              PngImageOutput() => JpegChroma.yuv420.index,
            },
            jpegBackgroundColor: switch (output) {
              JpegImageOutput() => output.backgroundColor,
              PngImageOutput() => 0xffffffff,
            },
            pngCompressionLevel: switch (output) {
              JpegImageOutput() => 6,
              PngImageOutput() => output.compressionLevel,
            },
            passthroughIfUnchanged: passthroughIfUnchanged,
          ),
        ),
        transfer: buffer,
      ),
    );
    return EncodedImage(
      bytes: result.bytes.toDart,
      width: result.width,
      height: result.height,
      format: ImageFormat.values[result.format],
    );
  }

  void _terminate([FfmpegException? error]) {
    if (_terminated) return;
    _terminated = true;
    _worker.terminate();
    _failAllPending(
      error ??
          const FfmpegException(
            -2,
            'image_ffmpeg Worker terminated during initialization',
          ),
    );
  }

  Future<JSObject> _request(
    _WorkerRequest Function(int id) build, {
    JSArrayBuffer? transfer,
  }) {
    if (_terminated) {
      throw StateError('image_ffmpeg Worker terminated unexpectedly');
    }
    final id = _nextRequestId++;
    final completer = Completer<JSObject>();
    _pending[id] = completer;
    _worker.postMessage(
      build(id),
      (transfer == null ? const <JSObject>[] : <JSObject>[transfer]).toJS,
    );
    return completer.future;
  }

  void _handleMessage(_MessageEvent event) {
    final response = _WorkerResponse.wrap(event.data);
    final completer = _pending.remove(response.id);
    if (completer == null) return;
    final error = response.error;
    if (error != null) {
      completer.completeError(
        FfmpegException(
          error.status ?? -1,
          error.message ?? 'Unknown image_ffmpeg worker error',
        ),
      );
      return;
    }
    final result = response.result;
    if (result == null) {
      completer.completeError(
        const FfmpegException(-1, 'image_ffmpeg worker returned no result'),
      );
      return;
    }
    completer.complete(result);
  }

  /// Fires when the worker script itself fails to load or throws at top
  /// level, for example when the assets are not bundled or served.
  void _handleError(_ErrorEvent event) {
    final detail = event.message;
    _terminate(
      FfmpegException(
        -2,
        'image_ffmpeg worker failed to load from $_workerUrl'
        '${detail == null || detail.isEmpty ? '' : ': $detail'}. Flutter web '
        'apps bundle it automatically; other embedders must serve '
        'package:image_ffmpeg/web/ and set ImageFfmpegWeb.workerUri.',
      ),
    );
  }

  void _failAllPending(FfmpegException error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }
}

/// Copies [bytes] into a fresh JS `ArrayBuffer` so that transferring the
/// buffer to the worker can never detach memory a caller still sees. Under
/// dart2js a `Uint8List.toJS` view can share the original buffer; under
/// dart2wasm `toJS` already copies out of linear memory.
JSArrayBuffer _transferableBuffer(Uint8List bytes) =>
    Uint8List.fromList(bytes).toJS.buffer;

extension _JSUint8ArrayToBuffer on JSUint8Array {
  external JSArrayBuffer get buffer;
}

@JS('document.baseURI')
external String get _documentBaseUri;

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external _Worker(String scriptURL, _WorkerOptions options);
  external void postMessage(JSAny? message, JSArray<JSObject> transfer);
  external set onmessage(JSFunction value);
  external set onerror(JSFunction value);
  external void terminate();
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSObject get data;
}

extension type _ErrorEvent._(JSObject _) implements JSObject {
  external String? get message;
}

/// One request for `lib/web/image_ffmpeg_worker.mjs`. Constructing this
/// object-literal type includes only the arguments that are passed, matching
/// the per-operation shapes the worker reads.
extension type _WorkerRequest._(JSObject _) implements JSObject {
  external factory _WorkerRequest({
    int id,
    String operation,
    JSArrayBuffer encoded,
    JSArrayBuffer bytes,
    int width,
    int height,
    int stride,
    int maxWidth,
    int maxHeight,
    int maxDimension,
    int alphaMode,
    int quality,
    int chroma,
    int backgroundColor,
    int compressionLevel,
    _TranscodeOptions options,
  });
}

extension type _TranscodeOptions._(JSObject _) implements JSObject {
  external factory _TranscodeOptions({
    int outputFormat,
    int maxWidth,
    int maxHeight,
    bool applyOrientation,
    int cropX,
    int cropY,
    int cropWidth,
    int cropHeight,
    int fillX,
    int fillY,
    int fillWidth,
    int fillHeight,
    int fillColor,
    int jpegQuality,
    int jpegChroma,
    int jpegBackgroundColor,
    int pngCompressionLevel,
    bool passthroughIfUnchanged,
  });
}

extension type _WorkerResponse.wrap(JSObject _) implements JSObject {
  external int get id;
  external JSObject? get result;
  external _WorkerError? get error;
}

extension type _WorkerError._(JSObject _) implements JSObject {
  external int? get status;
  external String? get message;
}

extension type _CapabilitiesResult.wrap(JSObject _) implements JSObject {
  external int get abiVersion;
  external bool get hasFfmpeg;
  external String get buildInfo;
}

extension type _ProbeResult.wrap(JSObject _) implements JSObject {
  external int get format;
  external int get width;
  external int get height;
  external int get displayWidth;
  external int get displayHeight;
  external int get orientation;
  external int get frameCount;
  external int get hasAlpha;
}

extension type _DecodeResult.wrap(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external int get width;
  external int get height;
  external int get stride;
  external int get pixelFormat;
}

extension type _EncodeResult.wrap(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
}

extension type _TranscodeResult.wrap(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external int get width;
  external int get height;
  external int get format;
}

RgbaImage _rgbaImageFromResult(_DecodeResult result) {
  if (result.pixelFormat != _pixelFormatRgba8888) {
    throw FfmpegException(
      -5,
      'Wasm module returned unsupported pixel format ${result.pixelFormat}',
    );
  }
  return RgbaImage(
    width: result.width,
    height: result.height,
    stride: result.stride,
    bytes: result.bytes.toDart,
  );
}
