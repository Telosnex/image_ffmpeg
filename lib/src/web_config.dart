/// Browser-only configuration for [Ffmpeg.load].
///
/// Native platforms ignore these settings entirely.
abstract final class FfmpegWeb {
  /// Where to load `image_ffmpeg_worker.mjs` from, before [Ffmpeg.load].
  ///
  /// When null, the Flutter web asset location
  /// `assets/packages/image_ffmpeg/web/image_ffmpeg_worker.mjs` is resolved
  /// against the document base URI, which works unchanged in Flutter web apps
  /// because this package declares its runtime as bundled assets.
  ///
  /// Non-Flutter embedders (for example `dart compile js` sites or browser
  /// tests) must serve this package's `lib/web/` directory somewhere
  /// same-origin and point this at the served `image_ffmpeg_worker.mjs`. The
  /// worker imports `image_ffmpeg_module.mjs` and `image_ffmpeg_module.wasm`
  /// relative to its own URL, so the three files must stay siblings.
  static Uri? workerUri;
}
