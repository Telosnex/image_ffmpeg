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
  /// When null, `native_prebuilt/image_ffmpeg/image_ffmpeg_worker.mjs` is
  /// resolved against the document base URI. In a Flutter web build, the
  /// image_ffmpeg build hook installs the four web files there
  /// (native_prebuilt ADR 002).
  ///
  /// Non-Flutter embedders (for example `dart compile js` sites or browser
  /// tests) must serve this package's `lib/web/` directory somewhere
  /// same-origin and point this at the served `image_ffmpeg_worker.mjs`. The
  /// worker imports `image_ffmpeg_module.mjs` and `image_ffmpeg_module.wasm`
  /// through `image_ffmpeg_loader.mjs` relative to its own URL. All four web
  /// assets must stay siblings. The query `v=<webRuntimeVersion>` is added
  /// unless this URI has a `v` query. The Worker passes its query to all
  /// three sibling assets.
  /// Set this before the first [ImageFfmpeg] operation. The shared page-wide
  /// Worker pool keeps its original URL afterward.
  static Uri? workerUri;
}
