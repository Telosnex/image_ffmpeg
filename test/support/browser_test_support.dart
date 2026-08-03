import 'dart:js_interop';
import 'dart:typed_data';

@JS()
external JSPromise<BrowserTestResponse> fetch(JSString url);

extension type BrowserTestResponse._(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// The test server maps `packages/image_ffmpeg/` to this package's `lib/`
/// relative to the generated test page, just as plain Dart browser consumers
/// are expected to serve `lib/web/`.
final servedWorkerUri = Uri.parse(
  'packages/image_ffmpeg/web/image_ffmpeg_worker.mjs',
);

Future<Uint8List> fetchTestAsset(String path) async {
  final response = await fetch(path.toJS).toDart;
  if (!response.ok) {
    throw StateError('GET $path returned HTTP ${response.status}');
  }
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}
