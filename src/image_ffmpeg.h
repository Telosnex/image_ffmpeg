#ifndef IMAGE_FFMPEG_H_
#define IMAGE_FFMPEG_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define IMAGE_FFMPEG_EXPORT __declspec(dllexport)
#else
#define IMAGE_FFMPEG_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Increment only when the C ABI changes incompatibly. Dart rejects a native or
// Wasm module with a different version before making any other calls.
#define IMAGE_FFMPEG_ABI_VERSION 5u

typedef enum image_ffmpeg_status {
  IMAGE_FFMPEG_OK = 0,
  IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT = -1,
  IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED = -2,
  IMAGE_FFMPEG_ERROR_DECODE = -3,
  IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY = -4,
  IMAGE_FFMPEG_ERROR_UNSUPPORTED = -5,
  IMAGE_FFMPEG_ERROR_NOT_IMAGE = -6,
  IMAGE_FFMPEG_ERROR_ENCODE = -7
} image_ffmpeg_status;

typedef enum image_ffmpeg_pixel_format {
  IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888 = 1
} image_ffmpeg_pixel_format;

typedef enum image_ffmpeg_box_alpha_mode {
  // Average all four channels from every source pixel.
  IMAGE_FFMPEG_BOX_ALPHA_INCLUDE = 0,
  // Ignore every source pixel whose alpha is not exactly 255. Retained cells
  // are opaque; cells without an opaque sample remain transparent black.
  IMAGE_FFMPEG_BOX_ALPHA_OPAQUE_ONLY = 1
} image_ffmpeg_box_alpha_mode;

typedef enum image_ffmpeg_image_format {
  IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN = 0,
  IMAGE_FFMPEG_IMAGE_FORMAT_JPEG = 1,
  IMAGE_FFMPEG_IMAGE_FORMAT_PNG = 2,
  IMAGE_FFMPEG_IMAGE_FORMAT_APNG = 3,
  IMAGE_FFMPEG_IMAGE_FORMAT_WEBP = 4,
  IMAGE_FFMPEG_IMAGE_FORMAT_GIF = 5,
  IMAGE_FFMPEG_IMAGE_FORMAT_BMP = 6,
  IMAGE_FFMPEG_IMAGE_FORMAT_TIFF = 7,
  IMAGE_FFMPEG_IMAGE_FORMAT_AVIF = 8,
  IMAGE_FFMPEG_IMAGE_FORMAT_PSD = 9,
  IMAGE_FFMPEG_IMAGE_FORMAT_ICO = 10
} image_ffmpeg_image_format;

// Values intentionally match EXIF Orientation tag values.
typedef enum image_ffmpeg_orientation {
  IMAGE_FFMPEG_ORIENTATION_NORMAL = 1,
  IMAGE_FFMPEG_ORIENTATION_FLIP_HORIZONTAL = 2,
  IMAGE_FFMPEG_ORIENTATION_ROTATE_180 = 3,
  IMAGE_FFMPEG_ORIENTATION_FLIP_VERTICAL = 4,
  IMAGE_FFMPEG_ORIENTATION_TRANSPOSE = 5,
  IMAGE_FFMPEG_ORIENTATION_ROTATE_90 = 6,
  IMAGE_FFMPEG_ORIENTATION_TRANSVERSE = 7,
  IMAGE_FFMPEG_ORIENTATION_ROTATE_270 = 8
} image_ffmpeg_orientation;

typedef enum image_ffmpeg_jpeg_chroma {
  IMAGE_FFMPEG_JPEG_CHROMA_420 = 0,
  IMAGE_FFMPEG_JPEG_CHROMA_444 = 1
} image_ffmpeg_jpeg_chroma;

// Owned output from image_ffmpeg_decode_image_rgba. Keep upstream AVFrame and
// AVCodecContext details out of this ABI: this exact struct is shared by FFI
// and Wasm, and remains stable when FFmpeg changes.
typedef struct image_ffmpeg_image {
  uint8_t *data;
  uint32_t length;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  uint32_t pixel_format;
} image_ffmpeg_image;

// Owned encoded bytes returned by an encoder operation.
typedef struct image_ffmpeg_buffer {
  uint8_t *data;
  uint32_t length;
} image_ffmpeg_buffer;

// Probe information without decoded pixels. has_alpha is -1 when the container
// cannot answer without decoding, 0 for no, and 1 for yes. frame_count is zero
// when the container does not advertise a count.
typedef struct image_ffmpeg_image_info {
  uint32_t format;
  uint32_t width;
  uint32_t height;
  uint32_t display_width;
  uint32_t display_height;
  uint32_t orientation;
  uint32_t frame_count;
  int32_t has_alpha;
} image_ffmpeg_image_info;

typedef struct image_ffmpeg_transcode_options {
  uint32_t output_format;
  uint32_t max_width;
  uint32_t max_height;
  uint32_t apply_orientation;
  uint32_t crop_x;
  uint32_t crop_y;
  uint32_t crop_width;
  uint32_t crop_height;
  uint32_t fill_x;
  uint32_t fill_y;
  uint32_t fill_width;
  uint32_t fill_height;
  uint32_t fill_argb;
  uint32_t jpeg_quality;
  uint32_t jpeg_chroma;
  uint32_t jpeg_background_argb;
  uint32_t png_compression_level;
  uint32_t passthrough_if_unchanged;
} image_ffmpeg_transcode_options;

typedef struct image_ffmpeg_encoded_image {
  uint8_t *data;
  uint32_t length;
  uint32_t width;
  uint32_t height;
  uint32_t format;
} image_ffmpeg_encoded_image;

IMAGE_FFMPEG_EXPORT uint32_t image_ffmpeg_abi_version(void);
IMAGE_FFMPEG_EXPORT const char *image_ffmpeg_build_info(void);
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_has_ffmpeg(void);

// Reads image format, geometry, EXIF orientation, frame count, and alpha hints
// without decoding a pixel buffer.
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_probe_image(
    const uint8_t *input,
    uint32_t input_length,
    image_ffmpeg_image_info *output);

// Probes arbitrary encoded bytes as an image, decodes the first frame, and
// returns tightly packed RGBA8888. A zero maximum preserves that axis. If both
// maxima are non-zero, aspect ratio is preserved and the image fits within the
// requested box without upscaling.
//
// This coarse operation is intentional: one boundary crossing owns probing,
// decode, scale, pixel conversion, and allocation on native and WebAssembly.
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_decode_image_rgba(
    const uint8_t *input,
    uint32_t input_length,
    uint32_t max_width,
    uint32_t max_height,
    image_ffmpeg_image *output);

// Decodes the first frame at full resolution and folds completed RGBA rows
// immediately into integer-only destination cells. POSIX native targets
// discard completed scratch pages, avoiding a resident full-resolution RGBA
// intermediate while preserving byte-identical full-frame color conversion.
// Only the small deterministic result crosses the language boundary. The result
// is never upscaled and max_dimension must be nonzero.
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_decode_image_rgba_box_average(
    const uint8_t *input,
    uint32_t input_length,
    uint32_t max_dimension,
    uint32_t alpha_mode,
    image_ffmpeg_image *output);

// Encodes RGBA8888 as JPEG. Quality is 1..100. background_argb is 0xAARRGGBB
// (the alpha byte is ignored); chroma is IMAGE_FFMPEG_JPEG_CHROMA_420 or _444.
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_encode_jpeg_rgba(
    const uint8_t *rgba,
    uint32_t rgba_length,
    uint32_t width,
    uint32_t height,
    uint32_t stride,
    uint32_t quality,
    uint32_t chroma,
    uint32_t background_argb,
    image_ffmpeg_buffer *output);

// Encodes RGBA8888 pixels as a complete PNG image, preserving alpha.
// Compression level is 0 (fastest) to 9 (smallest).
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_encode_png_rgba(
    const uint8_t *rgba,
    uint32_t rgba_length,
    uint32_t width,
    uint32_t height,
    uint32_t stride,
    uint32_t compression_level,
    image_ffmpeg_buffer *output);

// Fused first-frame decode, optional EXIF orientation, solid fill, crop,
// fit-within resize, and JPEG/PNG encode. Fill and crop coordinates are in
// oriented coordinates when apply_orientation is nonzero. Zero fill or crop
// width and height disable that operation.
IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_transcode_image(
    const uint8_t *input,
    uint32_t input_length,
    const image_ffmpeg_transcode_options *options,
    image_ffmpeg_encoded_image *output);

// Releases output->data and zeroes the struct. Safe on a zeroed image.
IMAGE_FFMPEG_EXPORT void image_ffmpeg_image_release(image_ffmpeg_image *image);
IMAGE_FFMPEG_EXPORT void image_ffmpeg_buffer_release(image_ffmpeg_buffer *buffer);
IMAGE_FFMPEG_EXPORT void image_ffmpeg_encoded_image_release(
    image_ffmpeg_encoded_image *image);

IMAGE_FFMPEG_EXPORT const char *image_ffmpeg_error_message(int32_t status);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // IMAGE_FFMPEG_H_
