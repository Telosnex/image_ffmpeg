@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:image_ffmpeg/src/backend/backend_web.dart';
import 'package:image_ffmpeg/src/web_runtime.g.dart';

/// native_prebuilt ADR 002 D7 and I3: every web runtime file loads with the
/// query `v=<webRuntimeVersion>`, so a browser does not use a cached file of
/// another version.
void main() {
  test('the worker URL has the webVersion query', () {
    const base = 'https://app.example/sub/';
    expect(
      resolveWorkerUrl(base, null).toString(),
      '${base}native_prebuilt/image_ffmpeg/image_ffmpeg_worker.mjs'
      '?v=$webRuntimeVersion',
    );
    expect(resolveWorkerUrl(base, Uri.parse('w/x.mjs?a=1')).queryParameters, {
      'a': '1',
      'v': webRuntimeVersion,
    });
    expect(
      resolveWorkerUrl(base, Uri.parse('x.mjs?v=pinned')).query,
      'v=pinned',
    );
  });

  test('the worker loads every file with the webVersion query', () async {
    final url = resolveWorkerUrl(
      _baseUri,
      Uri.parse('packages/image_ffmpeg/web/image_ffmpeg_worker.mjs'),
    );
    final worker = _Worker(url.toString().toJS, _WorkerOptions(type: 'module'));
    try {
      await _call(worker, 1, 'capabilities');
      final urls = [
        for (final name
            in ((await _call(worker, 2, 'resourceUrls'))! as JSArray<JSString>)
                .toDart)
          name.toDart,
      ];
      final loaded = urls.where((u) => u.contains('/image_ffmpeg_')).toList();
      expect(loaded.map((u) => Uri.parse(u).pathSegments.last).toSet(), {
        'image_ffmpeg_module.mjs',
        'image_ffmpeg_loader.mjs',
        'image_ffmpeg_module.wasm',
      });
      for (final u in loaded) {
        expect(Uri.parse(u).queryParameters['v'], webRuntimeVersion, reason: u);
      }
    } finally {
      worker.terminate();
    }
  });
}

final _pending = <int, Completer<_Message>>{};

Future<JSAny?> _call(_Worker worker, int id, String operation) async {
  worker.onmessage = ((_MessageEvent event) {
    final data = event.data as _Message;
    _pending.remove(data.id)?.complete(data);
  }).toJS;
  final completer = _pending[id] = Completer<_Message>();
  worker.postMessage(_Request(id: id, operation: operation));
  final data = await completer.future.timeout(const Duration(seconds: 30));
  if (data.error != null) {
    fail('worker $operation failed: ${data.error.dartify()}');
  }
  return data.result;
}

@JS('document.baseURI')
external String get _baseUri;

extension type _WorkerOptions._(JSObject _) implements JSObject {
  external factory _WorkerOptions({String type});
}

extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({int id, String operation});
}

extension type _Message._(JSObject _) implements JSObject {
  external int get id;
  external JSAny? get result;
  external JSAny? get error;
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString url, _WorkerOptions options);
  external void postMessage(JSAny? message);
  external void terminate();
  external set onmessage(JSFunction? handler);
}
