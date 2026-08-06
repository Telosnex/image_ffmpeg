/// FFmpeg behind one asynchronous Dart API.
///
/// Native platforms use a code asset through `dart:ffi`; browsers use a
/// separately compiled C/WebAssembly module behind the same API.
library;

export 'src/ffmpeg.dart' show ImageFfmpeg;
export 'src/web_config.dart' show ImageFfmpegWeb;
export 'src/models.dart'
    show
        BoxAverageAlphaMode,
        EncodedImage,
        FfmpegCapabilities,
        FfmpegException,
        FfmpegRuntime,
        ImageCrop,
        ImageFormat,
        ImageInfo,
        ImageOrientation,
        ImageOutput,
        JpegChroma,
        JpegImageOutput,
        PngImageOutput,
        RgbaImage;
