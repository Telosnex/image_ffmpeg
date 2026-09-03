import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:typed_data';

import '../models.dart';
import '../web_config.dart';
import 'backend.dart';

/// Must match `IMAGE_FFMPEG_ABI_VERSION` in `src/image_ffmpeg.h` and
/// `ABI_VERSION` in `lib/web/image_ffmpeg_loader.mjs`.
const _abiVersion = 5;

/// Must match `IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888` in `src/image_ffmpeg.h`.
const _pixelFormatRgba8888 = 1;

/// Flutter web bundles the pubspec-declared package assets at this app-origin
/// path; it is resolved against the document base URI so `<base href>` works.
// Version the default entry point by ABI. The Worker propagates this query to
// its loader, generated module, and Wasm binary, preventing a browser/CDN from
// combining assets from incompatible package revisions.
const _flutterAssetWorkerUrl =
    'assets/packages/image_ffmpeg/web/image_ffmpeg_worker.mjs?v=$_abiVersion';

/// Takes the API's call-time snapshot in JavaScript memory.
///
/// This keeps transfer from detaching caller-owned dart2js or JS-backed Wasm
/// input. It also avoids copying JS-backed Wasm input into Wasm memory and
/// then back into JavaScript before transfer.
Uint8List snapshotBytes(Uint8List bytes) => bytes.toJS.slice().toDart;

Future<FfmpegBackend> loadBackend() async {
  final workerCount = ImageFfmpegWeb.workerCount;
  if (workerCount < 1 || workerCount > 4) {
    throw RangeError.range(workerCount, 1, 4, 'ImageFfmpegWeb.workerCount');
  }
  final configuredUri =
      ImageFfmpegWeb.workerUri ?? Uri.parse(_flutterAssetWorkerUrl);
  final workerUrl = Uri.parse(
    _documentBaseUri,
  ).resolveUri(configuredUri).toString();
  final workers = <_WebWorkerBackend>[];
  try {
    for (var index = 0; index < workerCount; index++) {
      workers.add(_WebWorkerBackend(workerUrl));
    }
    final capabilities = await Future.wait(
      workers.map((worker) => worker.initialize()),
    );
    final expected = capabilities.first;
    for (final actual in capabilities) {
      if (actual.abiVersion != expected.abiVersion ||
          actual.canDecodeImage != expected.canDecodeImage ||
          actual.buildInfo != expected.buildInfo) {
        throw StateError(
          'image_ffmpeg Workers returned different capabilities',
        );
      }
    }
    return _WebPoolBackend(workerUrl, expected, workers);
  } on Object {
    for (final worker in workers) {
      worker.terminate();
    }
    rethrow;
  }
}

/// A bounded pool of independent Wasm runtimes.
final class _WebPoolBackend implements FfmpegBackend {
  _WebPoolBackend(
    this._workerUrl,
    this._capabilities,
    List<_WebWorkerBackend> workers,
  ) : _workers = workers.toSet(),
      _idleWorkers = Queue.of(workers) {
    for (final worker in workers) {
      worker.onIdleFailure = _handleIdleFailure;
    }
  }

  final String _workerUrl;
  final FfmpegCapabilities _capabilities;
  final Set<_WebWorkerBackend> _workers;
  final Queue<_WebWorkerBackend> _idleWorkers;
  final Queue<_QueuedOperation<Object?>> _operations = Queue();
  int _replacementsInProgress = 0;
  FfmpegException? _terminalError;

  @override
  FfmpegCapabilities get capabilities => _capabilities;

  @override
  Future<ImageInfo> probeImage(Uint8List encoded) {
    return _enqueue((worker) => worker.probeImage(encoded));
  }

  @override
  Future<RgbaImage> decodeImage(
    Uint8List encoded, {
    required int maxWidth,
    required int maxHeight,
  }) {
    return _enqueue(
      (worker) =>
          worker.decodeImage(encoded, maxWidth: maxWidth, maxHeight: maxHeight),
    );
  }

  @override
  Future<RgbaImage> decodeImageBoxAverage(
    Uint8List encoded, {
    required int maxDimension,
    required BoxAverageAlphaMode alphaMode,
  }) {
    return _enqueue(
      (worker) => worker.decodeImageBoxAverage(
        encoded,
        maxDimension: maxDimension,
        alphaMode: alphaMode,
      ),
    );
  }

  @override
  Future<Uint8List> encodeJpeg(
    RgbaImage image, {
    required int quality,
    required JpegChroma chroma,
    required int backgroundColor,
  }) {
    return _enqueue(
      (worker) => worker.encodeJpeg(
        image,
        quality: quality,
        chroma: chroma,
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  Future<Uint8List> encodePng(
    RgbaImage image, {
    required int compressionLevel,
  }) {
    return _enqueue(
      (worker) => worker.encodePng(image, compressionLevel: compressionLevel),
    );
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
  }) {
    return _enqueue(
      (worker) => worker.transcodeImage(
        encoded,
        output: output,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        applyOrientation: applyOrientation,
        crop: crop,
        fill: fill,
        passthroughIfUnchanged: passthroughIfUnchanged,
      ),
    );
  }

  Future<T> _enqueue<T>(
    Future<T> Function(_WebWorkerBackend worker) operation,
  ) {
    final terminalError = _terminalError;
    if (terminalError != null) return Future.error(terminalError);
    final queued = _QueuedOperation<T>(operation);
    _operations.add(queued as _QueuedOperation<Object?>);
    _pump();
    return queued.future;
  }

  void _pump() {
    while (_idleWorkers.isNotEmpty && _operations.isNotEmpty) {
      final worker = _idleWorkers.removeFirst();
      final operation = _operations.removeFirst();
      unawaited(_dispatch(worker, operation));
    }
  }

  Future<void> _dispatch(
    _WebWorkerBackend worker,
    _QueuedOperation<Object?> operation,
  ) async {
    try {
      operation.complete(await operation.run(worker));
      _idleWorkers.add(worker);
    } on _WorkerFailure catch (failure, stackTrace) {
      operation.completeError(failure.error, stackTrace);
      _removeFailedWorker(worker);
    } on Object catch (error, stackTrace) {
      operation.completeError(error, stackTrace);
      _idleWorkers.add(worker);
    }
    _pump();
  }

  void _handleIdleFailure(_WebWorkerBackend worker, FfmpegException error) {
    _removeFailedWorker(worker);
    _pump();
  }

  void _removeFailedWorker(_WebWorkerBackend worker) {
    if (!_workers.remove(worker)) return;
    _idleWorkers.remove(worker);
    worker.terminate();
    unawaited(_replaceWorker());
  }

  Future<void> _replaceWorker() async {
    _replacementsInProgress++;
    _WebWorkerBackend? replacement;
    try {
      replacement = _WebWorkerBackend(_workerUrl);
      final capabilities = await replacement.initialize();
      if (capabilities.abiVersion != _capabilities.abiVersion ||
          capabilities.canDecodeImage != _capabilities.canDecodeImage ||
          capabilities.buildInfo != _capabilities.buildInfo) {
        throw StateError(
          'replacement image_ffmpeg Worker returned different capabilities',
        );
      }
      replacement.onIdleFailure = _handleIdleFailure;
      _workers.add(replacement);
      _idleWorkers.add(replacement);
    } on Object catch (error) {
      replacement?.terminate();
      if (_workers.isEmpty && _replacementsInProgress == 1) {
        _terminalError = FfmpegException(
          -2,
          'image_ffmpeg has no live Workers after replacement failed: $error',
        );
      }
    } finally {
      _replacementsInProgress--;
    }
    if (_workers.isEmpty && _replacementsInProgress == 0) {
      _terminalError ??= const FfmpegException(
        -2,
        'image_ffmpeg has no live Workers',
      );
      _failQueued(_terminalError!);
    }
    _pump();
  }

  void _failQueued(FfmpegException error) {
    while (_operations.isNotEmpty) {
      _operations.removeFirst().completeError(error, StackTrace.current);
    }
  }
}

final class _QueuedOperation<T> {
  _QueuedOperation(this._operation);

  final Future<T> Function(_WebWorkerBackend worker) _operation;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  Future<T> run(_WebWorkerBackend worker) => _operation(worker);

  void complete(Object? value) => _completer.complete(value as T);

  void completeError(Object error, StackTrace stackTrace) =>
      _completer.completeError(error, stackTrace);
}

final class _WorkerFailure implements Exception {
  const _WorkerFailure(this.error);

  final FfmpegException error;
}

/// One module Worker and one Wasm runtime.
final class _WebWorkerBackend implements FfmpegBackend {
  _WebWorkerBackend(this._workerUrl)
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
  void Function(_WebWorkerBackend worker, FfmpegException error)? onIdleFailure;

  Future<FfmpegCapabilities> initialize() async {
    try {
      final result = _CapabilitiesResult.wrap(
        await _request(
          (id) => _WorkerRequest(id: id, operation: 'capabilities'),
        ),
      );
      if (result.abiVersion != _abiVersion) {
        throw StateError(
          'image_ffmpeg ABI mismatch: Dart expects $_abiVersion, Wasm module '
          'provides ${result.abiVersion}',
        );
      }
      return _capabilities = FfmpegCapabilities(
        runtime: FfmpegRuntime.webAssembly,
        abiVersion: result.abiVersion,
        buildInfo: result.buildInfo,
        canDecodeImage: result.hasFfmpeg,
      );
    } on _WorkerFailure catch (failure) {
      throw failure.error;
    }
  }

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
      format: ImageFormat.fromWireValue(result.format),
      width: result.width,
      height: result.height,
      displayWidth: result.displayWidth,
      displayHeight: result.displayHeight,
      orientation: ImageOrientation.fromWireValue(result.orientation),
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
          alphaMode: alphaMode.wireValue,
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
          chroma: chroma.wireValue,
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
            outputFormat: output.format.wireValue,
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
              JpegImageOutput() => output.chroma.wireValue,
              PngImageOutput() => JpegChroma.yuv420.wireValue,
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
      format: ImageFormat.fromWireValue(result.format),
    );
  }

  void terminate([FfmpegException? error]) {
    if (_terminated) return;
    _terminated = true;
    _worker.terminate();
    _failAllPending(
      _WorkerFailure(
        error ??
            const FfmpegException(
              -2,
              'image_ffmpeg Worker terminated during initialization',
            ),
      ),
    );
  }

  Future<JSObject> _request(
    _WorkerRequest Function(int id) build, {
    JSArrayBuffer? transfer,
  }) {
    if (_terminated) {
      return Future.error(
        const _WorkerFailure(
          FfmpegException(-2, 'image_ffmpeg Worker terminated unexpectedly'),
        ),
      );
    }
    if (_pending.isNotEmpty) {
      throw StateError('image_ffmpeg Worker received concurrent operations');
    }
    final id = _nextRequestId++;
    final completer = Completer<JSObject>();
    _pending[id] = completer;
    try {
      _worker.postMessage(
        build(id),
        (transfer == null ? const <JSObject>[] : <JSObject>[transfer]).toJS,
      );
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      completer.completeError(
        _WorkerFailure(
          FfmpegException(-2, 'image_ffmpeg Worker postMessage failed: $error'),
        ),
        stackTrace,
      );
    }
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
    final error = FfmpegException(
      -2,
      'image_ffmpeg worker failed to load from $_workerUrl'
      '${detail == null || detail.isEmpty ? '' : ': $detail'}. Flutter web '
      'apps bundle it automatically; other embedders must serve '
      'package:image_ffmpeg/web/ and set ImageFfmpegWeb.workerUri.',
    );
    final wasIdle = _pending.isEmpty;
    terminate(error);
    if (wasIdle) onIdleFailure?.call(this, error);
  }

  void _failAllPending(Object error) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }
}

/// Converts the pool-owned snapshot to a transferable buffer. Under dart2js,
/// transfer can detach this private snapshot. Under dart2wasm, `toJS` copies
/// the snapshot out of linear memory.
JSArrayBuffer _transferableBuffer(Uint8List bytes) => bytes.toJS.buffer;

extension _JSUint8ArrayToBuffer on JSUint8Array {
  external JSArrayBuffer get buffer;

  external JSUint8Array slice();
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
