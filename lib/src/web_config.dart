/// Browser-only configuration for [ImageFfmpeg].
///
/// Native platforms ignore these settings entirely.
abstract final class ImageFfmpegWeb {
  /// Number of module Workers in the browser pool.
  ///
  /// Each Worker owns one Wasm runtime and runs one operation at a time. The
  /// valid range is 1 through 4. The backend reads this value once during its
  /// first initialization. Set it before the first [ImageFfmpeg] operation.
  static int workerCount = 2;

  /// Where to load `image_ffmpeg_worker.mjs` from.
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
  /// through `image_ffmpeg_loader.mjs` relative to its own URL. All four web
  /// assets must stay siblings. A query string on this URI is propagated to
  /// all three sibling assets, allowing a host to use a per-build cache key
  /// without risking a mixed-ABI module graph.
  /// Set this before the first [ImageFfmpeg] operation. The shared page-wide
  /// Worker pool keeps its original URL afterward.
  static Uri? workerUri;
}
