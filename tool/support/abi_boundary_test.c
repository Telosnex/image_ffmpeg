#include "image_ffmpeg.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__,      \
              #condition);                                                     \
      exit(1);                                                                 \
    }                                                                          \
  } while (0)

static uint32_t fuzz_next(uint32_t *state) {
  *state ^= *state << 13;
  *state ^= *state >> 17;
  *state ^= *state << 5;
  return *state;
}

static int known_malformed_status(int32_t status) {
  return status == IMAGE_FFMPEG_OK || status == IMAGE_FFMPEG_ERROR_DECODE ||
         status == IMAGE_FFMPEG_ERROR_UNSUPPORTED ||
         status == IMAGE_FFMPEG_ERROR_NOT_IMAGE;
}

static void check_image_zero(const image_ffmpeg_image *image) {
  CHECK(image->data == NULL && image->length == 0 && image->width == 0 &&
        image->height == 0 && image->stride == 0 && image->pixel_format == 0);
}

static void check_buffer_zero(const image_ffmpeg_buffer *buffer) {
  CHECK(buffer->data == NULL && buffer->length == 0);
}

static void check_encoded_zero(const image_ffmpeg_encoded_image *image) {
  CHECK(image->data == NULL && image->length == 0 && image->width == 0 &&
        image->height == 0 && image->format == 0);
}

static image_ffmpeg_transcode_options png_options(void) {
  image_ffmpeg_transcode_options options;
  memset(&options, 0, sizeof(options));
  options.output_format = IMAGE_FFMPEG_IMAGE_FORMAT_PNG;
  options.apply_orientation = 1;
  options.jpeg_quality = 80;
  options.jpeg_chroma = IMAGE_FFMPEG_JPEG_CHROMA_420;
  options.jpeg_background_argb = 0xffffffffu;
  options.png_compression_level = 6;
  return options;
}

int main(int argc, char **argv) {
  const int quick = argc == 2 && strcmp(argv[1], "--quick") == 0;
  const int descriptor_cases = quick ? 256 : 4096;
  const int option_cases = quick ? 64 : 1024;
  const int mutation_cases = quick ? 64 : 1024;
  CHECK(image_ffmpeg_abi_version() == IMAGE_FFMPEG_ABI_VERSION);
  CHECK(image_ffmpeg_has_ffmpeg() == 1);
  CHECK(strstr(image_ffmpeg_build_info(), "image_ffmpeg ABI 5") != NULL);

  enum { width = 17, height = 13, stride = width * 4 + 11 };
  uint8_t rgba[stride * height];
  memset(rgba, 0xa5, sizeof(rgba));
  for (uint32_t y = 0; y < height; y++) {
    for (uint32_t x = 0; x < width; x++) {
      uint8_t *pixel = rgba + y * stride + x * 4;
      pixel[0] = (uint8_t)(x * 13 + y * 3);
      pixel[1] = (uint8_t)(x * 5 + y * 17);
      pixel[2] = (uint8_t)(x * 19 + y * 7);
      pixel[3] = (uint8_t)(255 - ((x + y) % 5) * 31);
    }
  }

  image_ffmpeg_buffer png = {0};
  CHECK(image_ffmpeg_encode_png_rgba(rgba, sizeof(rgba), width, height, stride,
                                     6, &png) == IMAGE_FFMPEG_OK);
  CHECK(png.data != NULL && png.length > 32);
  uint8_t *canonical_png = (uint8_t *)malloc(png.length);
  CHECK(canonical_png != NULL);
  memcpy(canonical_png, png.data, png.length);
  const uint32_t canonical_png_length = png.length;

  image_ffmpeg_image_info info;
  CHECK(image_ffmpeg_probe_image(png.data, png.length, &info) ==
        IMAGE_FFMPEG_OK);
  CHECK(info.format == IMAGE_FFMPEG_IMAGE_FORMAT_PNG && info.width == width &&
        info.height == height && info.orientation == IMAGE_FFMPEG_ORIENTATION_NORMAL);

  image_ffmpeg_image decoded = {0};
  CHECK(image_ffmpeg_decode_image_rgba(png.data, png.length, 0, 0, &decoded) ==
        IMAGE_FFMPEG_OK);
  CHECK(decoded.width == width && decoded.height == height &&
        decoded.stride == width * 4 &&
        decoded.pixel_format == IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888);
  for (uint32_t y = 0; y < height; y++) {
    CHECK(memcmp(decoded.data + y * decoded.stride, rgba + y * stride,
                 width * 4) == 0);
  }
  image_ffmpeg_image_release(&decoded);
  image_ffmpeg_image_release(&decoded);
  check_image_zero(&decoded);

  image_ffmpeg_buffer jpeg = {0};
  CHECK(image_ffmpeg_encode_jpeg_rgba(
            rgba, sizeof(rgba), width, height, stride, 92,
            IMAGE_FFMPEG_JPEG_CHROMA_444, 0xff102030u, &jpeg) ==
        IMAGE_FFMPEG_OK);
  CHECK(jpeg.data != NULL && jpeg.length > 32);
  CHECK(image_ffmpeg_decode_image_rgba(jpeg.data, jpeg.length, 9, 9, &decoded) ==
        IMAGE_FFMPEG_OK);
  CHECK(decoded.width == 9 && decoded.height == 6);
  image_ffmpeg_image_release(&decoded);

  image_ffmpeg_transcode_options options = png_options();
  options.max_width = 11;
  image_ffmpeg_encoded_image transcoded = {0};
  CHECK(image_ffmpeg_transcode_image(png.data, png.length, &options,
                                     &transcoded) == IMAGE_FFMPEG_OK);
  CHECK(transcoded.data != NULL && transcoded.width == 11 &&
        transcoded.height == 8 &&
        transcoded.format == IMAGE_FFMPEG_IMAGE_FORMAT_PNG);
  image_ffmpeg_encoded_image_release(&transcoded);
  image_ffmpeg_encoded_image_release(&transcoded);
  check_encoded_zero(&transcoded);

  memset(&decoded, 0xa5, sizeof(decoded));
  CHECK(image_ffmpeg_decode_image_rgba(NULL, 1, 0, 0, &decoded) ==
        IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT);
  check_image_zero(&decoded);
  memset(&info, 0xa5, sizeof(info));
  CHECK(image_ffmpeg_probe_image(NULL, 1, &info) ==
        IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT);
  CHECK(info.format == 0 && info.width == 0 && info.height == 0);
  memset(&transcoded, 0xa5, sizeof(transcoded));
  CHECK(image_ffmpeg_transcode_image(png.data, png.length, NULL, &transcoded) ==
        IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT);
  check_encoded_zero(&transcoded);

  uint32_t state = 0xc001d00du;
  uint8_t tiny[64];
  memset(tiny, 0x5a, sizeof(tiny));
  for (int iteration = 0; iteration < descriptor_cases; iteration++) {
    const uint32_t hostile_width = 1u + fuzz_next(&state);
    const uint32_t hostile_height = 1u + fuzz_next(&state);
    const uint32_t hostile_stride = fuzz_next(&state);
    image_ffmpeg_buffer output;
    memset(&output, 0xa5, sizeof(output));
    CHECK(image_ffmpeg_encode_png_rgba(
              tiny, sizeof(tiny), hostile_width, hostile_height, hostile_stride,
              fuzz_next(&state) % 10, &output) ==
          IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT);
    check_buffer_zero(&output);
    image_ffmpeg_buffer_release(&output);
  }

  for (int iteration = 0; iteration < option_cases; iteration++) {
    options = png_options();
    switch (iteration % 6) {
      case 0: options.output_format = IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN; break;
      case 1: options.apply_orientation = 2; break;
      case 2: options.crop_width = 1; break;
      case 3: options.jpeg_quality = 0; break;
      case 4: options.jpeg_chroma = 2; break;
      default: options.png_compression_level = 10; break;
    }
    memset(&transcoded, 0xa5, sizeof(transcoded));
    CHECK(image_ffmpeg_transcode_image(canonical_png, canonical_png_length,
                                       &options, &transcoded) ==
          IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT);
    check_encoded_zero(&transcoded);
    image_ffmpeg_encoded_image_release(&transcoded);
  }

  uint8_t *mutation = (uint8_t *)malloc(canonical_png_length);
  CHECK(mutation != NULL);
  for (int iteration = 0; iteration < mutation_cases; iteration++) {
    memcpy(mutation, canonical_png, canonical_png_length);
    const uint32_t mutations = 1 + fuzz_next(&state) % 4;
    for (uint32_t index = 0; index < mutations; index++) {
      const uint32_t offset = fuzz_next(&state) % canonical_png_length;
      mutation[offset] ^= (uint8_t)(1u << (fuzz_next(&state) & 7));
    }
    const uint32_t length = (iteration & 1)
                                ? 1 + fuzz_next(&state) % canonical_png_length
                                : canonical_png_length;
    memset(&info, 0xa5, sizeof(info));
    const int32_t probe_status = image_ffmpeg_probe_image(mutation, length, &info);
    CHECK(known_malformed_status(probe_status));
    if (probe_status == IMAGE_FFMPEG_OK) {
      CHECK(info.format != IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN && info.width > 0 &&
            info.height > 0 && info.orientation >= 1 && info.orientation <= 8);
    } else {
      CHECK(info.format == 0 && info.width == 0 && info.height == 0);
    }
    memset(&decoded, 0xa5, sizeof(decoded));
    const int32_t decode_status =
        image_ffmpeg_decode_image_rgba(mutation, length, 31, 29, &decoded);
    CHECK(known_malformed_status(decode_status));
    if (decode_status == IMAGE_FFMPEG_OK) {
      CHECK(decoded.data != NULL && decoded.width > 0 && decoded.height > 0 &&
            decoded.width <= 31 && decoded.height <= 29 &&
            decoded.stride >= decoded.width * 4 &&
            decoded.length >= decoded.stride * decoded.height &&
            decoded.pixel_format == IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888);
    } else {
      check_image_zero(&decoded);
    }
    image_ffmpeg_image_release(&decoded);
    check_image_zero(&decoded);
  }

  free(mutation);
  free(canonical_png);
  image_ffmpeg_buffer_release(&jpeg);
  image_ffmpeg_buffer_release(&png);
  image_ffmpeg_buffer_release(&jpeg);
  image_ffmpeg_buffer_release(&png);
  check_buffer_zero(&jpeg);
  check_buffer_zero(&png);
  printf("  positive PNG/JPEG/probe/decode/transcode ownership checks\n");
  printf("  malformed boundary corpus: %d deterministic cases\n",
         descriptor_cases + option_cases + mutation_cases);
  printf("PASS: image_ffmpeg ABI boundary suite\n");
  return 0;
}
