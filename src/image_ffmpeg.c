#include "image_ffmpeg.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
#include <libavcodec/avcodec.h>
#include <libavcodec/version.h>
#include <libavformat/avformat.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
#endif

// This is a portable ABI boundary, not an exposure of FFmpeg's ABI. All AV*
// types, probing, allocation, and ownership stay inside this translation unit.

IMAGE_FFMPEG_EXPORT uint32_t image_ffmpeg_abi_version(void) {
  return IMAGE_FFMPEG_ABI_VERSION;
}

IMAGE_FFMPEG_EXPORT const char *image_ffmpeg_build_info(void) {
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  return "image_ffmpeg ABI 4; " LIBAVCODEC_IDENT;
#else
  return "image_ffmpeg ABI 4; scaffold (FFmpeg not linked)";
#endif
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_has_ffmpeg(void) {
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  return 1;
#else
  return 0;
#endif
}

#if defined(IMAGE_FFMPEG_WITH_FFMPEG)

typedef struct image_ffmpeg_memory_input {
  const uint8_t *data;
  size_t length;
  size_t position;
} image_ffmpeg_memory_input;

// libswscale still accepts the legacy full-range YUVJ formats, but logs a
// warning and internally rewrites them to their range-neutral equivalents.
// Normalize before creating the context, then set the source range explicitly.
static enum AVPixelFormat image_ffmpeg_normalize_source_format(
    enum AVPixelFormat format, int *source_full_range) {
  switch (format) {
    case AV_PIX_FMT_YUVJ420P:
      *source_full_range = 1;
      return AV_PIX_FMT_YUV420P;
    case AV_PIX_FMT_YUVJ422P:
      *source_full_range = 1;
      return AV_PIX_FMT_YUV422P;
    case AV_PIX_FMT_YUVJ444P:
      *source_full_range = 1;
      return AV_PIX_FMT_YUV444P;
    case AV_PIX_FMT_YUVJ440P:
      *source_full_range = 1;
      return AV_PIX_FMT_YUV440P;
    case AV_PIX_FMT_YUVJ411P:
      *source_full_range = 1;
      return AV_PIX_FMT_YUV411P;
    default:
      return format;
  }
}

static int image_ffmpeg_set_source_full_range(struct SwsContext *context) {
  int *inverse_table;
  int *table;
  int source_range;
  int destination_range;
  int brightness;
  int contrast;
  int saturation;
  if (sws_getColorspaceDetails(context, &inverse_table, &source_range, &table,
                               &destination_range, &brightness, &contrast,
                               &saturation) < 0) {
    return -1;
  }
  return sws_setColorspaceDetails(context, inverse_table, 1, table,
                                  destination_range, brightness, contrast,
                                  saturation);
}

static int image_ffmpeg_read_memory(void *opaque, uint8_t *buffer,
                                   int buffer_size) {
  image_ffmpeg_memory_input *input = (image_ffmpeg_memory_input *)opaque;
  if (input->position >= input->length) return AVERROR_EOF;

  size_t remaining = input->length - input->position;
  size_t requested = (size_t)buffer_size;
  size_t count = remaining < requested ? remaining : requested;
  memcpy(buffer, input->data + input->position, count);
  input->position += count;
  return (int)count;
}

static int64_t image_ffmpeg_seek_memory(void *opaque, int64_t offset,
                                       int whence) {
  image_ffmpeg_memory_input *input = (image_ffmpeg_memory_input *)opaque;
  if ((whence & AVSEEK_SIZE) != 0) return (int64_t)input->length;

  int64_t base;
  switch (whence & ~AVSEEK_FORCE) {
    case SEEK_SET:
      base = 0;
      break;
    case SEEK_CUR:
      base = (int64_t)input->position;
      break;
    case SEEK_END:
      base = (int64_t)input->length;
      break;
    default:
      return AVERROR(EINVAL);
  }

  if (offset < -base) return AVERROR(EINVAL);
  int64_t position = base + offset;
  if (position < 0 || (uint64_t)position > input->length) {
    return AVERROR(EINVAL);
  }
  input->position = (size_t)position;
  return position;
}

static uint16_t image_ffmpeg_read_le16(const uint8_t *data) {
  return (uint16_t)(data[0] | ((uint16_t)data[1] << 8));
}

static uint32_t image_ffmpeg_read_le32(const uint8_t *data) {
  return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
         ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static uint16_t image_ffmpeg_read_be16(const uint8_t *data) {
  return (uint16_t)(((uint16_t)data[0] << 8) | data[1]);
}

static uint32_t image_ffmpeg_read_be32(const uint8_t *data) {
  return ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) |
         ((uint32_t)data[2] << 8) | data[3];
}

static uint16_t image_ffmpeg_tiff_u16(const uint8_t *data, int little_endian) {
  return little_endian ? image_ffmpeg_read_le16(data)
                       : image_ffmpeg_read_be16(data);
}

static uint32_t image_ffmpeg_tiff_u32(const uint8_t *data, int little_endian) {
  return little_endian ? image_ffmpeg_read_le32(data)
                       : image_ffmpeg_read_be32(data);
}

static uint32_t image_ffmpeg_tiff_orientation(const uint8_t *tiff,
                                             size_t length) {
  if (length < 8) return IMAGE_FFMPEG_ORIENTATION_NORMAL;
  int little_endian;
  if (tiff[0] == 'I' && tiff[1] == 'I')
    little_endian = 1;
  else if (tiff[0] == 'M' && tiff[1] == 'M')
    little_endian = 0;
  else
    return IMAGE_FFMPEG_ORIENTATION_NORMAL;
  if (image_ffmpeg_tiff_u16(tiff + 2, little_endian) != 42) {
    return IMAGE_FFMPEG_ORIENTATION_NORMAL;
  }
  uint32_t ifd_offset = image_ffmpeg_tiff_u32(tiff + 4, little_endian);
  if (ifd_offset > length || length - ifd_offset < 2) {
    return IMAGE_FFMPEG_ORIENTATION_NORMAL;
  }
  const uint8_t *ifd = tiff + ifd_offset;
  uint32_t count = image_ffmpeg_tiff_u16(ifd, little_endian);
  if (count > (length - ifd_offset - 2) / 12) {
    return IMAGE_FFMPEG_ORIENTATION_NORMAL;
  }
  for (uint32_t index = 0; index < count; index++) {
    const uint8_t *entry = ifd + 2 + (size_t)index * 12;
    if (image_ffmpeg_tiff_u16(entry, little_endian) == 0x0112 &&
        image_ffmpeg_tiff_u16(entry + 2, little_endian) == 3 &&
        image_ffmpeg_tiff_u32(entry + 4, little_endian) == 1) {
      uint32_t orientation = image_ffmpeg_tiff_u16(entry + 8, little_endian);
      return orientation >= 1 && orientation <= 8
                 ? orientation
                 : IMAGE_FFMPEG_ORIENTATION_NORMAL;
    }
  }
  return IMAGE_FFMPEG_ORIENTATION_NORMAL;
}

// Finds EXIF TIFF payloads in JPEG, PNG, WebP, and standalone TIFF images.
static uint32_t image_ffmpeg_exif_orientation(const uint8_t *input,
                                             size_t length) {
  static const uint8_t png_signature[8] = {0x89, 'P', 'N', 'G',
                                           0x0d, 0x0a, 0x1a, 0x0a};
  if (length >= 8 &&
      ((input[0] == 'I' && input[1] == 'I') ||
       (input[0] == 'M' && input[1] == 'M'))) {
    return image_ffmpeg_tiff_orientation(input, length);
  }
  if (length >= 4 && input[0] == 0xff && input[1] == 0xd8) {
    size_t offset = 2;
    while (offset + 4 <= length) {
      if (input[offset] != 0xff) break;
      uint8_t marker = input[offset + 1];
      offset += 2;
      if (marker == 0xd9 || marker == 0xda) break;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      uint16_t segment_length = image_ffmpeg_read_be16(input + offset);
      if (segment_length < 2 || segment_length > length - offset) break;
      if (marker == 0xe1 && segment_length >= 8 &&
          memcmp(input + offset + 2, "Exif\0\0", 6) == 0) {
        return image_ffmpeg_tiff_orientation(input + offset + 8,
                                            segment_length - 8);
      }
      offset += segment_length;
    }
  } else if (length >= 8 &&
             memcmp(input, png_signature, sizeof(png_signature)) == 0) {
    size_t offset = 8;
    while (offset + 12 <= length) {
      uint32_t chunk_length = image_ffmpeg_read_be32(input + offset);
      if (chunk_length > length - offset - 12) break;
      if (memcmp(input + offset + 4, "eXIf", 4) == 0) {
        return image_ffmpeg_tiff_orientation(input + offset + 8,
                                            chunk_length);
      }
      offset += (size_t)chunk_length + 12;
    }
  } else if (length >= 12 && memcmp(input, "RIFF", 4) == 0 &&
             memcmp(input + 8, "WEBP", 4) == 0) {
    size_t offset = 12;
    while (offset + 8 <= length) {
      uint32_t chunk_length = image_ffmpeg_read_le32(input + offset + 4);
      if (chunk_length > length - offset - 8) break;
      if (memcmp(input + offset, "EXIF", 4) == 0) {
        const uint8_t *exif = input + offset + 8;
        size_t exif_length = chunk_length;
        if (exif_length >= 6 && memcmp(exif, "Exif\0\0", 6) == 0) {
          exif += 6;
          exif_length -= 6;
        }
        return image_ffmpeg_tiff_orientation(exif, exif_length);
      }
      offset += 8 + (size_t)chunk_length + (chunk_length & 1u);
    }
  }
  return IMAGE_FFMPEG_ORIENTATION_NORMAL;
}

typedef struct image_ffmpeg_ico_selection {
  int stream_index;
  uint32_t width;
  uint32_t height;
  uint32_t bits_per_pixel;
  uint32_t data_offset;
  uint32_t data_size;
  int is_png;
} image_ffmpeg_ico_selection;

// Returns 1 for a valid ICO, 0 for another format, and -1 for a malformed ICO
// header. The largest image is preferred, with bit depth breaking area ties.
static int image_ffmpeg_select_ico(const uint8_t *input, size_t input_length,
                                  image_ffmpeg_ico_selection *selection) {
  static const uint8_t png_signature[8] = {0x89, 'P', 'N', 'G',
                                           0x0d, 0x0a, 0x1a, 0x0a};
  if (input_length < 6 || image_ffmpeg_read_le16(input) != 0 ||
      image_ffmpeg_read_le16(input + 2) != 1) {
    return 0;
  }

  uint32_t count = image_ffmpeg_read_le16(input + 4);
  if (count == 0 || count > (input_length - 6) / 16) return -1;

  memset(selection, 0, sizeof(*selection));
  selection->stream_index = -1;
  uint64_t best_area = 0;
  for (uint32_t index = 0; index < count; index++) {
    const uint8_t *entry = input + 6 + (size_t)index * 16;
    uint32_t width = entry[0] == 0 ? 256 : entry[0];
    uint32_t height = entry[1] == 0 ? 256 : entry[1];
    uint32_t bits_per_pixel = image_ffmpeg_read_le16(entry + 6);
    uint32_t data_size = image_ffmpeg_read_le32(entry + 8);
    uint32_t data_offset = image_ffmpeg_read_le32(entry + 12);
    if (data_size < 8 || data_offset > input_length ||
        data_size > input_length - data_offset) {
      continue;
    }

    const uint8_t *image = input + data_offset;
    int is_png = memcmp(image, png_signature, sizeof(png_signature)) == 0;
    if (!is_png &&
        (data_size < 40 || image_ffmpeg_read_le32(image) != 40)) {
      continue;
    }
    if (!is_png && bits_per_pixel == 0 && data_size >= 16) {
      bits_per_pixel = image_ffmpeg_read_le16(image + 14);
    }

    uint64_t area = (uint64_t)width * height;
    if (selection->stream_index < 0 || area > best_area ||
        (area == best_area &&
         bits_per_pixel > selection->bits_per_pixel)) {
      selection->stream_index = (int)index;
      selection->width = width;
      selection->height = height;
      selection->bits_per_pixel = bits_per_pixel;
      selection->data_offset = data_offset;
      selection->data_size = data_size;
      selection->is_png = is_png;
      best_area = area;
    }
  }
  return selection->stream_index < 0 ? -1 : 1;
}

// Extracts the 1-bit AND transparency mask from a classic BMP-backed ICO.
// Returns 1 with an owned, top-down GRAY8 plane, 0 when no separate mask is
// needed, or a negative AVERROR for malformed data/allocation failure.
static int image_ffmpeg_ico_alpha_mask(
    const uint8_t *input, size_t input_length,
    const image_ffmpeg_ico_selection *selection, uint8_t **mask_data,
    uint32_t *mask_width, uint32_t *mask_height) {
  *mask_data = NULL;
  *mask_width = 0;
  *mask_height = 0;
  if (selection->is_png) return 0;
  if (selection->data_size < 40 || selection->data_offset > input_length ||
      selection->data_size > input_length - selection->data_offset) {
    return AVERROR_INVALIDDATA;
  }

  const uint8_t *dib = input + selection->data_offset;
  int32_t dib_width = (int32_t)image_ffmpeg_read_le32(dib + 4);
  int32_t doubled_height = (int32_t)image_ffmpeg_read_le32(dib + 8);
  uint32_t bits_per_pixel = image_ffmpeg_read_le16(dib + 14);
  uint32_t compression = image_ffmpeg_read_le32(dib + 16);
  uint32_t colors_used = image_ffmpeg_read_le32(dib + 32);
  if (bits_per_pixel >= 32) return 0;
  if (dib_width <= 0 || doubled_height == 0 ||
      doubled_height == INT32_MIN || bits_per_pixel == 0 || compression != 0) {
    return AVERROR_INVALIDDATA;
  }

  uint32_t width = (uint32_t)dib_width;
  uint32_t total_height = (uint32_t)(doubled_height < 0 ? -doubled_height
                                                        : doubled_height);
  if ((total_height & 1) != 0) return AVERROR_INVALIDDATA;
  uint32_t height = total_height / 2;
  if (width != selection->width || height != selection->height ||
      (uint64_t)width * height > SIZE_MAX) {
    return AVERROR_INVALIDDATA;
  }

  uint32_t palette_entries = colors_used;
  if (palette_entries == 0 && bits_per_pixel <= 8) {
    palette_entries = 1u << bits_per_pixel;
  }
  uint64_t xor_offset = 40u + (uint64_t)palette_entries * 4u;
  uint64_t xor_stride = (((uint64_t)width * bits_per_pixel + 31u) / 32u) * 4u;
  uint64_t mask_stride = (((uint64_t)width + 31u) / 32u) * 4u;
  uint64_t mask_offset = xor_offset + xor_stride * height;
  uint64_t required_size = mask_offset + mask_stride * height;
  if (required_size > selection->data_size) return AVERROR_INVALIDDATA;

  uint8_t *alpha = (uint8_t *)malloc((size_t)width * height);
  if (alpha == NULL) return AVERROR(ENOMEM);
  const uint8_t *mask = dib + mask_offset;
  int bottom_up = doubled_height > 0;
  for (uint32_t y = 0; y < height; y++) {
    uint32_t mask_y = bottom_up ? height - 1 - y : y;
    const uint8_t *row = mask + (size_t)mask_y * mask_stride;
    for (uint32_t x = 0; x < width; x++) {
      alpha[(size_t)y * width + x] =
          (row[x / 8] & (uint8_t)(0x80u >> (x & 7))) != 0 ? 0 : 255;
    }
  }
  *mask_data = alpha;
  *mask_width = width;
  *mask_height = height;
  return 1;
}

static int image_ffmpeg_has_iso_brand(const char *brands,
                                     const char expected[4]) {
  if (brands == NULL) return 0;
  size_t length = strlen(brands);
  for (size_t offset = 0; offset + 4 <= length; offset += 4) {
    if (memcmp(brands + offset, expected, 4) == 0) return 1;
  }
  return 0;
}

static int image_ffmpeg_is_avif(AVFormatContext *format_context) {
  const AVDictionaryEntry *major_brand =
      av_dict_get(format_context->metadata, "major_brand", NULL, 0);
  const AVDictionaryEntry *compatible_brands =
      av_dict_get(format_context->metadata, "compatible_brands", NULL, 0);
  const char *major = major_brand == NULL ? NULL : major_brand->value;
  const char *compatible =
      compatible_brands == NULL ? NULL : compatible_brands->value;
  return image_ffmpeg_has_iso_brand(major, "avif") ||
         image_ffmpeg_has_iso_brand(major, "avis") ||
         image_ffmpeg_has_iso_brand(compatible, "avif") ||
         image_ffmpeg_has_iso_brand(compatible, "avis");
}

static int image_ffmpeg_is_image_codec(AVFormatContext *format_context,
                                      enum AVCodecID codec_id) {
  switch (codec_id) {
    case AV_CODEC_ID_MJPEG:
    case AV_CODEC_ID_PNG:
    case AV_CODEC_ID_APNG:
    case AV_CODEC_ID_WEBP:
    case AV_CODEC_ID_WEBP_ANIM:
    case AV_CODEC_ID_GIF:
    case AV_CODEC_ID_BMP:
    case AV_CODEC_ID_TIFF:
    case AV_CODEC_ID_PSD:
      return 1;
    case AV_CODEC_ID_AV1:
      // AV1 also appears in ordinary MP4 video. Only accept it when the
      // ISO-BMFF brands explicitly identify AVIF/AVIS image content.
      return image_ffmpeg_is_avif(format_context);
    default:
      return 0;
  }
}

static int image_ffmpeg_is_alpha_stream(const AVStream *stream);

static uint32_t image_ffmpeg_format_for_stream(
    AVFormatContext *format_context, const AVStream *stream, int is_ico) {
  if (is_ico) return IMAGE_FFMPEG_IMAGE_FORMAT_ICO;
  switch (stream->codecpar->codec_id) {
    case AV_CODEC_ID_MJPEG:
      return IMAGE_FFMPEG_IMAGE_FORMAT_JPEG;
    case AV_CODEC_ID_APNG:
      return IMAGE_FFMPEG_IMAGE_FORMAT_APNG;
    case AV_CODEC_ID_PNG:
      return format_context->iformat != NULL &&
                     strcmp(format_context->iformat->name, "apng") == 0
                 ? IMAGE_FFMPEG_IMAGE_FORMAT_APNG
                 : IMAGE_FFMPEG_IMAGE_FORMAT_PNG;
    case AV_CODEC_ID_WEBP:
    case AV_CODEC_ID_WEBP_ANIM:
      return IMAGE_FFMPEG_IMAGE_FORMAT_WEBP;
    case AV_CODEC_ID_GIF:
      return IMAGE_FFMPEG_IMAGE_FORMAT_GIF;
    case AV_CODEC_ID_BMP:
      return IMAGE_FFMPEG_IMAGE_FORMAT_BMP;
    case AV_CODEC_ID_TIFF:
      return IMAGE_FFMPEG_IMAGE_FORMAT_TIFF;
    case AV_CODEC_ID_AV1:
      return image_ffmpeg_is_avif(format_context)
                 ? IMAGE_FFMPEG_IMAGE_FORMAT_AVIF
                 : IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN;
    case AV_CODEC_ID_PSD:
      return IMAGE_FFMPEG_IMAGE_FORMAT_PSD;
    default:
      return IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN;
  }
}

static int32_t image_ffmpeg_alpha_hint(AVFormatContext *format_context,
                                      const AVStream *stream, int is_ico,
                                      const image_ffmpeg_ico_selection *ico) {
  if (is_ico) {
    if (ico->is_png || ico->bits_per_pixel == 32) return 1;
    return ico->bits_per_pixel < 32 ? 1 : -1;  // Classic ICO AND mask.
  }
  if (stream->codecpar->codec_id == AV_CODEC_ID_AV1) {
    for (unsigned index = 0; index < format_context->nb_streams; index++) {
      if (format_context->streams[index] != stream &&
          image_ffmpeg_is_alpha_stream(format_context->streams[index])) {
        return 1;
      }
    }
  }
  const AVPixFmtDescriptor *description = NULL;
  if (stream->codecpar->format >= 0) {
    description =
        av_pix_fmt_desc_get((enum AVPixelFormat)stream->codecpar->format);
    if (description != NULL &&
        (description->flags & AV_PIX_FMT_FLAG_ALPHA) != 0) {
      return 1;
    }
  }
  switch (stream->codecpar->codec_id) {
    case AV_CODEC_ID_MJPEG:
    case AV_CODEC_ID_AV1:
      return 0;
    case AV_CODEC_ID_GIF:
    case AV_CODEC_ID_WEBP:
    case AV_CODEC_ID_WEBP_ANIM:
      // Transparency can be signaled by a palette entry or container feature
      // that is not reflected in codecpar->format.
      return -1;
    case AV_CODEC_ID_PNG:
    case AV_CODEC_ID_APNG:
      if (stream->codecpar->format == AV_PIX_FMT_PAL8) return -1;
      return description == NULL ? -1 : 0;
    case AV_CODEC_ID_BMP:
    case AV_CODEC_ID_TIFF:
    case AV_CODEC_ID_PSD:
      return description == NULL ? -1 : 0;
    default:
      return -1;
  }
}

static int image_ffmpeg_is_alpha_stream(const AVStream *stream) {
  const AVDictionaryEntry *title =
      av_dict_get(stream->metadata, "title", NULL, 0);
  return title != NULL && strcmp(title->value, "Alpha") == 0;
}

static int image_ffmpeg_receive_first_frames(
    AVFormatContext *format_context, AVCodecContext *color_codec_context,
    int color_stream_index, AVFrame *color_frame,
    AVCodecContext *alpha_codec_context, int alpha_stream_index,
    AVFrame *alpha_frame, AVPacket *packet) {
  int color_received = 0;
  int alpha_received = alpha_codec_context == NULL;
  int result;

  while ((result = av_read_frame(format_context, packet)) >= 0) {
    AVCodecContext *codec_context = NULL;
    AVFrame *frame = NULL;
    int *received = NULL;
    if (packet->stream_index == color_stream_index && !color_received) {
      codec_context = color_codec_context;
      frame = color_frame;
      received = &color_received;
    } else if (packet->stream_index == alpha_stream_index && !alpha_received) {
      codec_context = alpha_codec_context;
      frame = alpha_frame;
      received = &alpha_received;
    }

    if (codec_context != NULL) {
      result = avcodec_send_packet(codec_context, packet);
      av_packet_unref(packet);
      if (result < 0 && result != AVERROR(EAGAIN)) return result;

      result = avcodec_receive_frame(codec_context, frame);
      if (result >= 0)
        *received = 1;
      else if (result != AVERROR(EAGAIN))
        return result;
    } else {
      av_packet_unref(packet);
    }

    if (color_received && alpha_received) return 0;
  }

  // Some decoders delay their first frame until end-of-stream.
  if (!color_received) {
    result = avcodec_send_packet(color_codec_context, NULL);
    if (result < 0 && result != AVERROR_EOF) return result;
    result = avcodec_receive_frame(color_codec_context, color_frame);
    if (result < 0) return result;
    color_received = 1;
  }
  if (!alpha_received) {
    result = avcodec_send_packet(alpha_codec_context, NULL);
    if (result < 0 && result != AVERROR_EOF) return result;
    result = avcodec_receive_frame(alpha_codec_context, alpha_frame);
    if (result < 0) return result;
    alpha_received = 1;
  }
  return color_received && alpha_received ? 0 : AVERROR_INVALIDDATA;
}

#endif

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_probe_image(
    const uint8_t *input, uint32_t input_length,
    image_ffmpeg_image_info *output) {
  if (input == NULL || input_length == 0 || output == NULL) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  memset(output, 0, sizeof(*output));
  output->orientation = IMAGE_FFMPEG_ORIENTATION_NORMAL;
  output->has_alpha = -1;
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  const int avio_buffer_size = 4096;
  int32_t status = IMAGE_FFMPEG_ERROR_DECODE;
  int stream_index = -1;
  int ico_status;
  image_ffmpeg_ico_selection ico_selection;
  AVIOContext *avio_context = NULL;
  AVFormatContext *format_context = NULL;
  uint8_t *avio_buffer = NULL;
  image_ffmpeg_memory_input memory_input = {input, input_length, 0};

  ico_status = image_ffmpeg_select_ico(input, input_length, &ico_selection);
  if (ico_status < 0) goto cleanup;
  avio_buffer = (uint8_t *)av_malloc((size_t)avio_buffer_size);
  if (avio_buffer == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  avio_context = avio_alloc_context(
      avio_buffer, avio_buffer_size, 0, &memory_input, image_ffmpeg_read_memory,
      NULL, image_ffmpeg_seek_memory);
  if (avio_context == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  avio_buffer = NULL;
  format_context = avformat_alloc_context();
  if (format_context == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  format_context->pb = avio_context;
  format_context->flags |= AVFMT_FLAG_CUSTOM_IO;
  if (avformat_open_input(&format_context, NULL, NULL, NULL) < 0) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }
  // Populate dimensions, pixel-format hints, and advertised frame counts.
  avformat_find_stream_info(format_context, NULL);
  stream_index = ico_status > 0
                     ? ico_selection.stream_index
                     : av_find_best_stream(format_context, AVMEDIA_TYPE_VIDEO,
                                           -1, -1, NULL, 0);
  if (stream_index < 0 ||
      (unsigned)stream_index >= format_context->nb_streams) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }
  AVStream *stream = format_context->streams[stream_index];
  if (!image_ffmpeg_is_image_codec(format_context,
                                  stream->codecpar->codec_id)) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }
  uint32_t format = image_ffmpeg_format_for_stream(
      format_context, stream, ico_status > 0);
  if (format == IMAGE_FFMPEG_IMAGE_FORMAT_UNKNOWN) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }
  int width = ico_status > 0 ? (int)ico_selection.width
                             : stream->codecpar->width;
  int height = ico_status > 0 ? (int)ico_selection.height
                              : stream->codecpar->height;
  if (width <= 0 || height <= 0 ||
      (int64_t)width * height > 100000000) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }
  uint32_t orientation = image_ffmpeg_exif_orientation(input, input_length);
  output->format = format;
  output->width = (uint32_t)width;
  output->height = (uint32_t)height;
  output->orientation = orientation;
  output->display_width = orientation >= 5 ? (uint32_t)height : (uint32_t)width;
  output->display_height = orientation >= 5 ? (uint32_t)width : (uint32_t)height;
  output->frame_count =
      stream->nb_frames > 0 && (uint64_t)stream->nb_frames <= UINT32_MAX
          ? (uint32_t)stream->nb_frames
          : 0;
  if (output->frame_count == 0 && format != IMAGE_FFMPEG_IMAGE_FORMAT_APNG &&
      format != IMAGE_FFMPEG_IMAGE_FORMAT_GIF &&
      format != IMAGE_FFMPEG_IMAGE_FORMAT_WEBP) {
    output->frame_count = 1;
  }
  output->has_alpha = image_ffmpeg_alpha_hint(
      format_context, stream, ico_status > 0, &ico_selection);
  status = IMAGE_FFMPEG_OK;

cleanup:
  avformat_close_input(&format_context);
  if (avio_context != NULL) {
    av_freep(&avio_context->buffer);
    avio_context_free(&avio_context);
  }
  av_free(avio_buffer);
  return status;
#else
  return IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED;
#endif
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_decode_image_rgba(
    const uint8_t *input,
    uint32_t input_length,
    uint32_t max_width,
    uint32_t max_height,
    image_ffmpeg_image *output) {
  if (input == NULL || input_length == 0 || output == NULL) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  memset(output, 0, sizeof(*output));

#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  const int avio_buffer_size = 4096;
  const int64_t max_source_pixels = 100000000;
  int32_t status = IMAGE_FFMPEG_ERROR_DECODE;
  int stream_index = -1;
  int alpha_stream_index = -1;
  int ico_status;
  image_ffmpeg_ico_selection ico_selection;
  AVIOContext *avio_context = NULL;
  AVFormatContext *format_context = NULL;
  AVCodecContext *codec_context = NULL;
  AVCodecContext *alpha_codec_context = NULL;
  const AVCodec *alpha_codec = NULL;
  AVPacket *packet = NULL;
  AVFrame *frame = NULL;
  AVFrame *alpha_frame = NULL;
  struct SwsContext *scale_context = NULL;
  struct SwsContext *alpha_scale_context = NULL;
  uint8_t *avio_buffer = NULL;
  uint8_t *rgba = NULL;
  uint8_t *alpha = NULL;
  uint8_t *ico_alpha = NULL;
  uint32_t ico_alpha_width = 0;
  uint32_t ico_alpha_height = 0;
  image_ffmpeg_memory_input memory_input = {input, input_length, 0};

  ico_status = image_ffmpeg_select_ico(input, input_length, &ico_selection);
  if (ico_status < 0) {
    status = IMAGE_FFMPEG_ERROR_DECODE;
    goto cleanup;
  }

  avio_buffer = (uint8_t *)av_malloc((size_t)avio_buffer_size);
  if (avio_buffer == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  avio_context = avio_alloc_context(
      avio_buffer, avio_buffer_size, 0, &memory_input, image_ffmpeg_read_memory,
      NULL, image_ffmpeg_seek_memory);
  if (avio_context == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  // Ownership of the buffer has moved into the AVIO context.
  avio_buffer = NULL;

  format_context = avformat_alloc_context();
  if (format_context == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  format_context->pb = avio_context;
  format_context->flags |= AVFMT_FLAG_CUSTOM_IO;

  if (avformat_open_input(&format_context, NULL, NULL, NULL) < 0) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }

  if (ico_status > 0) {
    stream_index = ico_selection.stream_index;
    if (stream_index < 0 ||
        (unsigned)stream_index >= format_context->nb_streams) {
      status = IMAGE_FFMPEG_ERROR_DECODE;
      goto cleanup;
    }
  } else {
    stream_index = av_find_best_stream(format_context, AVMEDIA_TYPE_VIDEO, -1,
                                       -1, NULL, 0);
  }
  if (stream_index < 0) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }

  AVStream *stream = format_context->streams[stream_index];
  if (stream->codecpar->codec_id == AV_CODEC_ID_AV1 &&
      (stream->disposition & AV_DISPOSITION_DEPENDENT) != 0) {
    // FFmpeg exposes AVIF grid cells as dependent streams but does not compose
    // the primary grid image. Reject rather than return one tile.
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }
  if (!image_ffmpeg_is_image_codec(format_context,
                                  stream->codecpar->codec_id)) {
    status = IMAGE_FFMPEG_ERROR_NOT_IMAGE;
    goto cleanup;
  }
  const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
  if (codec == NULL) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }

  if (stream->codecpar->codec_id == AV_CODEC_ID_AV1) {
    for (unsigned index = 0; index < format_context->nb_streams; index++) {
      AVStream *candidate = format_context->streams[index];
      if ((int)index != stream_index &&
          candidate->codecpar->codec_id == AV_CODEC_ID_AV1 &&
          image_ffmpeg_is_alpha_stream(candidate)) {
        alpha_stream_index = (int)index;
        break;
      }
    }
  }

  codec_context = avcodec_alloc_context3(codec);
  packet = av_packet_alloc();
  frame = av_frame_alloc();
  if (alpha_stream_index >= 0) {
    AVStream *alpha_stream = format_context->streams[alpha_stream_index];
    alpha_codec = avcodec_find_decoder(alpha_stream->codecpar->codec_id);
    if (alpha_codec == NULL) {
      status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
      goto cleanup;
    }
    alpha_codec_context = avcodec_alloc_context3(alpha_codec);
    alpha_frame = av_frame_alloc();
  }
  if (codec_context == NULL || packet == NULL || frame == NULL ||
      (alpha_stream_index >= 0 &&
       (alpha_codec_context == NULL || alpha_frame == NULL))) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  if (avcodec_parameters_to_context(codec_context, stream->codecpar) < 0) {
    goto cleanup;
  }

  // Bound decompression bombs before the decoder allocates frame storage. The
  // first release keeps this fixed; a future options struct can make it caller
  // configurable without changing the coarse operation.
  codec_context->max_pixels = max_source_pixels;
  codec_context->thread_count = 1;
  if (avcodec_open2(codec_context, codec, NULL) < 0) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }
  if (alpha_codec_context != NULL) {
    AVStream *alpha_stream = format_context->streams[alpha_stream_index];
    if (avcodec_parameters_to_context(alpha_codec_context,
                                      alpha_stream->codecpar) < 0) {
      goto cleanup;
    }
    alpha_codec_context->max_pixels = max_source_pixels;
    alpha_codec_context->thread_count = 1;
    if (avcodec_open2(alpha_codec_context, alpha_codec, NULL) < 0) {
      status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
      goto cleanup;
    }
  }

  if (image_ffmpeg_receive_first_frames(
          format_context, codec_context, stream_index, frame,
          alpha_codec_context, alpha_stream_index, alpha_frame, packet) < 0) {
    goto cleanup;
  }
  if (frame->width <= 0 || frame->height <= 0 ||
      (int64_t)frame->width * frame->height > max_source_pixels) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }

  if (ico_status > 0) {
    int mask_status = image_ffmpeg_ico_alpha_mask(
        input, input_length, &ico_selection, &ico_alpha, &ico_alpha_width,
        &ico_alpha_height);
    if (mask_status == AVERROR(ENOMEM)) {
      status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
      goto cleanup;
    }
    if (mask_status < 0) {
      status = IMAGE_FFMPEG_ERROR_DECODE;
      goto cleanup;
    }
  }

  uint32_t destination_width = (uint32_t)frame->width;
  uint32_t destination_height = (uint32_t)frame->height;
  if (max_width != 0 || max_height != 0) {
    const uint64_t width_limit = max_width == 0 ? UINT32_MAX : max_width;
    const uint64_t height_limit = max_height == 0 ? UINT32_MAX : max_height;

    if ((uint64_t)frame->width > width_limit ||
        (uint64_t)frame->height > height_limit) {
      if (width_limit * (uint64_t)frame->height <=
          height_limit * (uint64_t)frame->width) {
        destination_width = (uint32_t)width_limit;
        destination_height =
            (uint32_t)(((uint64_t)frame->height * destination_width) /
                       (uint64_t)frame->width);
      } else {
        destination_height = (uint32_t)height_limit;
        destination_width =
            (uint32_t)(((uint64_t)frame->width * destination_height) /
                       (uint64_t)frame->height);
      }
      if (destination_width == 0) destination_width = 1;
      if (destination_height == 0) destination_height = 1;
    }
  }
  if (destination_width > INT_MAX || destination_height > INT_MAX) {
    status = IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
    goto cleanup;
  }

  const int rgba_size = av_image_get_buffer_size(
      AV_PIX_FMT_RGBA, (int)destination_width, (int)destination_height, 1);
  if (rgba_size < 0) goto cleanup;
  rgba = (uint8_t *)malloc((size_t)rgba_size);
  if (rgba == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }

  uint8_t *destination_data[4] = {NULL, NULL, NULL, NULL};
  int destination_linesize[4] = {0, 0, 0, 0};
  if (av_image_fill_arrays(destination_data, destination_linesize, rgba,
                           AV_PIX_FMT_RGBA, (int)destination_width,
                           (int)destination_height, 1) < 0) {
    goto cleanup;
  }

  int source_full_range = frame->color_range == AVCOL_RANGE_JPEG;
  enum AVPixelFormat source_format = image_ffmpeg_normalize_source_format(
      (enum AVPixelFormat)frame->format, &source_full_range);
  scale_context = sws_getContext(
      frame->width, frame->height, source_format, (int)destination_width,
      (int)destination_height, AV_PIX_FMT_RGBA, SWS_AREA, NULL, NULL, NULL);
  if (scale_context == NULL ||
      (source_full_range &&
       image_ffmpeg_set_source_full_range(scale_context) < 0) ||
      sws_scale(scale_context, (const uint8_t *const *)frame->data,
                frame->linesize, 0, frame->height, destination_data,
                destination_linesize) != (int)destination_height) {
    goto cleanup;
  }

  if (alpha_frame != NULL || ico_alpha != NULL) {
    int alpha_source_width;
    int alpha_source_height;
    enum AVPixelFormat alpha_source_format;
    const uint8_t *alpha_source_data[4] = {NULL, NULL, NULL, NULL};
    int alpha_source_linesize[4] = {0, 0, 0, 0};
    if (alpha_frame != NULL) {
      if (alpha_frame->width <= 0 || alpha_frame->height <= 0 ||
          (int64_t)alpha_frame->width * alpha_frame->height >
              max_source_pixels) {
        goto cleanup;
      }
      alpha_source_width = alpha_frame->width;
      alpha_source_height = alpha_frame->height;
      alpha_source_format = (enum AVPixelFormat)alpha_frame->format;
      for (int index = 0; index < 4; index++) {
        alpha_source_data[index] = alpha_frame->data[index];
        alpha_source_linesize[index] = alpha_frame->linesize[index];
      }
    } else {
      alpha_source_width = (int)ico_alpha_width;
      alpha_source_height = (int)ico_alpha_height;
      alpha_source_format = AV_PIX_FMT_GRAY8;
      alpha_source_data[0] = ico_alpha;
      alpha_source_linesize[0] = (int)ico_alpha_width;
    }

    size_t alpha_size = (size_t)destination_width * destination_height;
    alpha = (uint8_t *)malloc(alpha_size);
    if (alpha == NULL) {
      status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
      goto cleanup;
    }
    uint8_t *alpha_data[4] = {alpha, NULL, NULL, NULL};
    int alpha_linesize[4] = {(int)destination_width, 0, 0, 0};
    alpha_scale_context = sws_getContext(
        alpha_source_width, alpha_source_height, alpha_source_format,
        (int)destination_width, (int)destination_height, AV_PIX_FMT_GRAY8,
        SWS_AREA, NULL, NULL, NULL);
    if (alpha_scale_context == NULL ||
        sws_scale(alpha_scale_context, alpha_source_data,
                  alpha_source_linesize, 0, alpha_source_height, alpha_data,
                  alpha_linesize) != (int)destination_height) {
      goto cleanup;
    }
    for (uint32_t y = 0; y < destination_height; y++) {
      for (uint32_t x = 0; x < destination_width; x++) {
        rgba[(size_t)y * destination_linesize[0] + (size_t)x * 4 + 3] =
            alpha[(size_t)y * destination_width + x];
      }
    }
  }

  output->data = rgba;
  output->length = (uint32_t)rgba_size;
  output->width = destination_width;
  output->height = destination_height;
  output->stride = (uint32_t)destination_linesize[0];
  output->pixel_format = IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888;
  rgba = NULL;
  status = IMAGE_FFMPEG_OK;

cleanup:
  free(ico_alpha);
  free(alpha);
  free(rgba);
  sws_freeContext(alpha_scale_context);
  sws_freeContext(scale_context);
  av_frame_free(&alpha_frame);
  av_frame_free(&frame);
  av_packet_free(&packet);
  avcodec_free_context(&alpha_codec_context);
  avcodec_free_context(&codec_context);
  avformat_close_input(&format_context);
  if (avio_context != NULL) {
    av_freep(&avio_context->buffer);
    avio_context_free(&avio_context);
  }
  av_free(avio_buffer);
  return status;
#else
  (void)max_width;
  (void)max_height;
  return IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED;
#endif
}

static int32_t image_ffmpeg_box_average_rgba(
    image_ffmpeg_image *image, uint32_t max_dimension, uint32_t alpha_mode) {
  if (image == NULL || image->data == NULL || image->width == 0 ||
      image->height == 0 || image->stride < image->width * 4u ||
      image->pixel_format != IMAGE_FFMPEG_PIXEL_FORMAT_RGBA8888 ||
      max_dimension == 0 ||
      alpha_mode > IMAGE_FFMPEG_BOX_ALPHA_OPAQUE_ONLY) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }

  const uint32_t source_width = image->width;
  const uint32_t source_height = image->height;
  uint32_t destination_width = source_width;
  uint32_t destination_height = source_height;
  if (source_width > max_dimension || source_height > max_dimension) {
    if (source_width >= source_height) {
      destination_width = max_dimension;
      destination_height = (uint32_t)(
          ((uint64_t)source_height * max_dimension) / source_width);
    } else {
      destination_height = max_dimension;
      destination_width = (uint32_t)(
          ((uint64_t)source_width * max_dimension) / source_height);
    }
    if (destination_width == 0) destination_width = 1;
    if (destination_height == 0) destination_height = 1;
  }

  const uint64_t destination_length =
      (uint64_t)destination_width * destination_height * 4u;
  if (destination_length > UINT32_MAX) {
    return IMAGE_FFMPEG_ERROR_UNSUPPORTED;
  }
  uint8_t *destination = (uint8_t *)calloc(1, (size_t)destination_length);
  if (destination == NULL) return IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;

  for (uint32_t destination_y = 0; destination_y < destination_height;
       destination_y++) {
    const uint32_t source_y_start = (uint32_t)(
        ((uint64_t)destination_y * source_height + destination_height - 1u) /
        destination_height);
    const uint32_t source_y_end = (uint32_t)(
        ((uint64_t)(destination_y + 1u) * source_height +
         destination_height - 1u) /
        destination_height);
    for (uint32_t destination_x = 0; destination_x < destination_width;
         destination_x++) {
      const uint32_t source_x_start = (uint32_t)(
          ((uint64_t)destination_x * source_width + destination_width - 1u) /
          destination_width);
      const uint32_t source_x_end = (uint32_t)(
          ((uint64_t)(destination_x + 1u) * source_width +
           destination_width - 1u) /
          destination_width);
      uint64_t red = 0;
      uint64_t green = 0;
      uint64_t blue = 0;
      uint64_t alpha = 0;
      uint64_t count = 0;
      for (uint32_t source_y = source_y_start; source_y < source_y_end;
           source_y++) {
        const uint8_t *pixel = image->data +
                               (size_t)source_y * image->stride +
                               (size_t)source_x_start * 4u;
        for (uint32_t source_x = source_x_start; source_x < source_x_end;
             source_x++, pixel += 4) {
          if (alpha_mode == IMAGE_FFMPEG_BOX_ALPHA_OPAQUE_ONLY &&
              pixel[3] != 255u) {
            continue;
          }
          red += pixel[0];
          green += pixel[1];
          blue += pixel[2];
          alpha += pixel[3];
          count++;
        }
      }
      if (count == 0) continue;

      const uint64_t half = count >> 1;
      uint8_t *output_pixel =
          destination +
          ((size_t)destination_y * destination_width + destination_x) * 4u;
      output_pixel[0] = (uint8_t)((red + half) / count);
      output_pixel[1] = (uint8_t)((green + half) / count);
      output_pixel[2] = (uint8_t)((blue + half) / count);
      output_pixel[3] =
          alpha_mode == IMAGE_FFMPEG_BOX_ALPHA_OPAQUE_ONLY
              ? 255u
              : (uint8_t)((alpha + half) / count);
    }
  }

  free(image->data);
  image->data = destination;
  image->length = (uint32_t)destination_length;
  image->width = destination_width;
  image->height = destination_height;
  image->stride = destination_width * 4u;
  return IMAGE_FFMPEG_OK;
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_decode_image_rgba_box_average(
    const uint8_t *input, uint32_t input_length, uint32_t max_dimension,
    uint32_t alpha_mode, image_ffmpeg_image *output) {
  if (output == NULL) return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  memset(output, 0, sizeof(*output));
  if (input == NULL || input_length == 0 || max_dimension == 0 ||
      alpha_mode > IMAGE_FFMPEG_BOX_ALPHA_OPAQUE_ONLY) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }

  int32_t status =
      image_ffmpeg_decode_image_rgba(input, input_length, 0, 0, output);
  if (status != IMAGE_FFMPEG_OK) return status;
  status = image_ffmpeg_box_average_rgba(output, max_dimension, alpha_mode);
  if (status != IMAGE_FFMPEG_OK) image_ffmpeg_image_release(output);
  return status;
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_decode_jpeg_rgba(
    const uint8_t *input,
    uint32_t input_length,
    uint32_t max_width,
    uint32_t max_height,
    image_ffmpeg_image *output) {
  return image_ffmpeg_decode_image_rgba(input, input_length, max_width,
                                       max_height, output);
}

#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
static int32_t image_ffmpeg_encode_rgba(
    const uint8_t *rgba, uint32_t width, uint32_t height, uint32_t stride,
    enum AVCodecID codec_id, uint32_t option, uint32_t jpeg_chroma,
    uint32_t jpeg_background_argb, image_ffmpeg_buffer *output) {
  int32_t status = IMAGE_FFMPEG_ERROR_ENCODE;
  const AVCodec *codec = NULL;
  AVCodecContext *codec_context = NULL;
  AVFrame *frame = NULL;
  AVPacket *packet = NULL;
  struct SwsContext *scale_context = NULL;
  uint8_t *jpeg_rgb = NULL;
  uint8_t *encoded = NULL;

  codec = avcodec_find_encoder(codec_id);
  if (codec == NULL) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }
  codec_context = avcodec_alloc_context3(codec);
  frame = av_frame_alloc();
  packet = av_packet_alloc();
  if (codec_context == NULL || frame == NULL || packet == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }

  codec_context->width = (int)width;
  codec_context->height = (int)height;
  codec_context->time_base = (AVRational){1, 1};
  codec_context->thread_count = 1;
  if (codec_id == AV_CODEC_ID_MJPEG) {
    codec_context->pix_fmt = jpeg_chroma == IMAGE_FFMPEG_JPEG_CHROMA_444
                                 ? AV_PIX_FMT_YUV444P
                                 : AV_PIX_FMT_YUV420P;
    codec_context->color_range = AVCOL_RANGE_JPEG;
    // FFmpeg's MJPEG encoder uses a 2 (best) to 31 (worst) quantizer. Expose a
    // conventional quality scale while keeping its endpoints reachable.
    int quantizer =
        2 + (int)(((uint64_t)(100 - option) * 29u + 49u) / 99u);
    codec_context->flags |= AV_CODEC_FLAG_QSCALE;
    codec_context->global_quality = FF_QP2LAMBDA * quantizer;
  } else {
    codec_context->pix_fmt = AV_PIX_FMT_RGBA;
    codec_context->compression_level = (int)option;
    // Adaptive row filters are dramatically smaller than unfiltered RGBA for
    // most images and remain lossless. Compression level still controls zlib.
    if (av_opt_set_int(codec_context->priv_data, "pred", 5, 0) < 0) {
      goto cleanup;
    }
  }

  if (avcodec_open2(codec_context, codec, NULL) < 0) {
    status = IMAGE_FFMPEG_ERROR_UNSUPPORTED;
    goto cleanup;
  }

  frame->format = codec_context->pix_fmt;
  frame->width = codec_context->width;
  frame->height = codec_context->height;
  frame->color_range = codec_context->color_range;
  frame->quality = codec_context->global_quality;
  frame->pts = 0;
  if (av_frame_get_buffer(frame, 32) < 0) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }

  enum AVPixelFormat source_format = AV_PIX_FMT_RGBA;
  const uint8_t *source_data[4] = {rgba, NULL, NULL, NULL};
  int source_linesize[4] = {(int)stride, 0, 0, 0};
  if (codec_id == AV_CODEC_ID_MJPEG) {
    size_t rgb_stride = (size_t)width * 3u;
    jpeg_rgb = (uint8_t *)malloc(rgb_stride * height);
    if (jpeg_rgb == NULL) {
      status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
      goto cleanup;
    }
    const uint32_t background[3] = {
        (jpeg_background_argb >> 16) & 0xffu,
        (jpeg_background_argb >> 8) & 0xffu,
        jpeg_background_argb & 0xffu,
    };
    for (uint32_t y = 0; y < height; y++) {
      const uint8_t *source_row = rgba + (size_t)y * stride;
      uint8_t *destination_row = jpeg_rgb + (size_t)y * rgb_stride;
      for (uint32_t x = 0; x < width; x++) {
        uint32_t alpha = source_row[(size_t)x * 4u + 3u];
        for (uint32_t channel = 0; channel < 3; channel++) {
          uint32_t color = source_row[(size_t)x * 4u + channel];
          destination_row[(size_t)x * 3u + channel] = (uint8_t)(
              (color * alpha + background[channel] * (255u - alpha) + 127u) /
              255u);
        }
      }
    }
    source_format = AV_PIX_FMT_RGB24;
    source_data[0] = jpeg_rgb;
    source_linesize[0] = (int)rgb_stride;
  }
  scale_context = sws_getContext(
      (int)width, (int)height, source_format, (int)width, (int)height,
      codec_context->pix_fmt, SWS_BILINEAR, NULL, NULL, NULL);
  if (scale_context != NULL && codec_id == AV_CODEC_ID_MJPEG) {
    const int *coefficients = sws_getCoefficients(SWS_CS_ITU601);
    if (sws_setColorspaceDetails(scale_context, coefficients, 1, coefficients,
                                 1, 0, 1 << 16, 1 << 16) < 0) {
      goto cleanup;
    }
  }
  if (scale_context == NULL ||
      sws_scale(scale_context, source_data, source_linesize, 0, (int)height,
                frame->data, frame->linesize) != (int)height) {
    goto cleanup;
  }

  int result = avcodec_send_frame(codec_context, frame);
  if (result < 0) goto cleanup;
  result = avcodec_receive_packet(codec_context, packet);
  if (result == AVERROR(EAGAIN)) {
    result = avcodec_send_frame(codec_context, NULL);
    if (result < 0 && result != AVERROR_EOF) goto cleanup;
    result = avcodec_receive_packet(codec_context, packet);
  }
  if (result < 0 || packet->size <= 0) goto cleanup;

  encoded = (uint8_t *)malloc((size_t)packet->size);
  if (encoded == NULL) {
    status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
    goto cleanup;
  }
  memcpy(encoded, packet->data, (size_t)packet->size);
  output->data = encoded;
  output->length = (uint32_t)packet->size;
  encoded = NULL;
  status = IMAGE_FFMPEG_OK;

cleanup:
  free(encoded);
  free(jpeg_rgb);
  sws_freeContext(scale_context);
  av_packet_free(&packet);
  av_frame_free(&frame);
  avcodec_free_context(&codec_context);
  return status;
}
#endif

static int32_t image_ffmpeg_validate_encode_arguments(
    const uint8_t *rgba, uint32_t rgba_length, uint32_t width,
    uint32_t height, uint32_t stride, uint32_t option, uint32_t option_min,
    uint32_t option_max, image_ffmpeg_buffer *output) {
  const uint64_t max_source_pixels = 100000000;
  if (output == NULL) return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  memset(output, 0, sizeof(*output));
  if (rgba == NULL || width == 0 || height == 0 || width > INT_MAX ||
      height > INT_MAX || stride > INT_MAX ||
      (uint64_t)width * height > max_source_pixels ||
      (uint64_t)width * 4u > stride ||
      (uint64_t)stride * height > rgba_length || option < option_min ||
      option > option_max) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  return IMAGE_FFMPEG_OK;
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_encode_jpeg_rgba_ex(
    const uint8_t *rgba, uint32_t rgba_length, uint32_t width,
    uint32_t height, uint32_t stride, uint32_t quality, uint32_t chroma,
    uint32_t background_argb, image_ffmpeg_buffer *output) {
  int32_t status = image_ffmpeg_validate_encode_arguments(
      rgba, rgba_length, width, height, stride, quality, 1, 100, output);
  if (status != IMAGE_FFMPEG_OK) return status;
  if (chroma > IMAGE_FFMPEG_JPEG_CHROMA_444) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  return image_ffmpeg_encode_rgba(rgba, width, height, stride,
                                 AV_CODEC_ID_MJPEG, quality, chroma,
                                 background_argb, output);
#else
  (void)background_argb;
  return IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED;
#endif
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_encode_jpeg_rgba(
    const uint8_t *rgba, uint32_t rgba_length, uint32_t width,
    uint32_t height, uint32_t stride, uint32_t quality,
    image_ffmpeg_buffer *output) {
  return image_ffmpeg_encode_jpeg_rgba_ex(
      rgba, rgba_length, width, height, stride, quality,
      IMAGE_FFMPEG_JPEG_CHROMA_420, 0xffffffffu, output);
}

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_encode_png_rgba(
    const uint8_t *rgba, uint32_t rgba_length, uint32_t width,
    uint32_t height, uint32_t stride, uint32_t compression_level,
    image_ffmpeg_buffer *output) {
  int32_t status = image_ffmpeg_validate_encode_arguments(
      rgba, rgba_length, width, height, stride, compression_level, 0, 9,
      output);
  if (status != IMAGE_FFMPEG_OK) return status;
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  return image_ffmpeg_encode_rgba(rgba, width, height, stride, AV_CODEC_ID_PNG,
                                 compression_level, 0, 0, output);
#else
  return IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED;
#endif
}

#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
static int32_t image_ffmpeg_orient_rgba(image_ffmpeg_image *image,
                                       uint32_t orientation) {
  if (orientation == IMAGE_FFMPEG_ORIENTATION_NORMAL) return IMAGE_FFMPEG_OK;
  uint32_t source_width = image->width;
  uint32_t source_height = image->height;
  uint32_t width = orientation >= 5 ? source_height : source_width;
  uint32_t height = orientation >= 5 ? source_width : source_height;
  size_t length = (size_t)width * height * 4u;
  uint8_t *data = (uint8_t *)malloc(length);
  if (data == NULL) return IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
  for (uint32_t y = 0; y < height; y++) {
    for (uint32_t x = 0; x < width; x++) {
      uint32_t source_x;
      uint32_t source_y;
      switch (orientation) {
        case IMAGE_FFMPEG_ORIENTATION_FLIP_HORIZONTAL:
          source_x = source_width - 1 - x;
          source_y = y;
          break;
        case IMAGE_FFMPEG_ORIENTATION_ROTATE_180:
          source_x = source_width - 1 - x;
          source_y = source_height - 1 - y;
          break;
        case IMAGE_FFMPEG_ORIENTATION_FLIP_VERTICAL:
          source_x = x;
          source_y = source_height - 1 - y;
          break;
        case IMAGE_FFMPEG_ORIENTATION_TRANSPOSE:
          source_x = y;
          source_y = x;
          break;
        case IMAGE_FFMPEG_ORIENTATION_ROTATE_90:
          source_x = y;
          source_y = source_height - 1 - x;
          break;
        case IMAGE_FFMPEG_ORIENTATION_TRANSVERSE:
          source_x = source_width - 1 - y;
          source_y = source_height - 1 - x;
          break;
        case IMAGE_FFMPEG_ORIENTATION_ROTATE_270:
          source_x = source_width - 1 - y;
          source_y = x;
          break;
        default:
          free(data);
          return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
      }
      memcpy(data + ((size_t)y * width + x) * 4u,
             image->data + (size_t)source_y * image->stride +
                 (size_t)source_x * 4u,
             4);
    }
  }
  free(image->data);
  image->data = data;
  image->length = (uint32_t)length;
  image->width = width;
  image->height = height;
  image->stride = width * 4u;
  return IMAGE_FFMPEG_OK;
}

static int32_t image_ffmpeg_crop_rgba(image_ffmpeg_image *image, uint32_t x,
                                     uint32_t y, uint32_t width,
                                     uint32_t height) {
  if (width == 0 && height == 0) return IMAGE_FFMPEG_OK;
  if (width == 0 || height == 0 || x > image->width || y > image->height ||
      width > image->width - x || height > image->height - y) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  if (x == 0 && y == 0 && width == image->width && height == image->height) {
    return IMAGE_FFMPEG_OK;
  }
  size_t stride = (size_t)width * 4u;
  size_t length = stride * height;
  uint8_t *data = (uint8_t *)malloc(length);
  if (data == NULL) return IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
  for (uint32_t row = 0; row < height; row++) {
    memcpy(data + (size_t)row * stride,
           image->data + (size_t)(y + row) * image->stride + (size_t)x * 4u,
           stride);
  }
  free(image->data);
  image->data = data;
  image->length = (uint32_t)length;
  image->width = width;
  image->height = height;
  image->stride = (uint32_t)stride;
  return IMAGE_FFMPEG_OK;
}

static int32_t image_ffmpeg_fill_rgba(image_ffmpeg_image *image, uint32_t x,
                                     uint32_t y, uint32_t width,
                                     uint32_t height, uint32_t color_argb) {
  if (width == 0 && height == 0) return IMAGE_FFMPEG_OK;
  if (width == 0 || height == 0 || x > image->width || y > image->height ||
      width > image->width - x || height > image->height - y) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  const uint8_t color[4] = {
      (uint8_t)((color_argb >> 16) & 0xffu),
      (uint8_t)((color_argb >> 8) & 0xffu),
      (uint8_t)(color_argb & 0xffu),
      (uint8_t)((color_argb >> 24) & 0xffu),
  };
  for (uint32_t row = y; row < y + height; row++) {
    uint8_t *pixel = image->data + (size_t)row * image->stride +
                     (size_t)x * 4u;
    for (uint32_t column = 0; column < width; column++, pixel += 4) {
      memcpy(pixel, color, sizeof(color));
    }
  }
  return IMAGE_FFMPEG_OK;
}

static int32_t image_ffmpeg_fit_rgba(image_ffmpeg_image *image,
                                    uint32_t max_width,
                                    uint32_t max_height) {
  uint32_t width = image->width;
  uint32_t height = image->height;
  uint64_t width_limit = max_width == 0 ? UINT32_MAX : max_width;
  uint64_t height_limit = max_height == 0 ? UINT32_MAX : max_height;
  if ((uint64_t)width <= width_limit && (uint64_t)height <= height_limit) {
    return IMAGE_FFMPEG_OK;
  }
  uint32_t destination_width;
  uint32_t destination_height;
  if (width_limit * height <= height_limit * width) {
    destination_width = (uint32_t)width_limit;
    destination_height =
        (uint32_t)(((uint64_t)height * destination_width) / width);
  } else {
    destination_height = (uint32_t)height_limit;
    destination_width =
        (uint32_t)(((uint64_t)width * destination_height) / height);
  }
  if (destination_width == 0) destination_width = 1;
  if (destination_height == 0) destination_height = 1;
  if (destination_width > INT_MAX || destination_height > INT_MAX) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  size_t length = (size_t)destination_width * destination_height * 4u;
  uint8_t *data = (uint8_t *)malloc(length);
  if (data == NULL) return IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
  uint8_t *destination_data[4] = {data, NULL, NULL, NULL};
  int destination_linesize[4] = {(int)destination_width * 4, 0, 0, 0};
  const uint8_t *source_data[4] = {image->data, NULL, NULL, NULL};
  int source_linesize[4] = {(int)image->stride, 0, 0, 0};
  struct SwsContext *context = sws_getContext(
      (int)width, (int)height, AV_PIX_FMT_RGBA, (int)destination_width,
      (int)destination_height, AV_PIX_FMT_RGBA, SWS_AREA, NULL, NULL, NULL);
  if (context == NULL ||
      sws_scale(context, source_data, source_linesize, 0, (int)height,
                destination_data, destination_linesize) !=
          (int)destination_height) {
    sws_freeContext(context);
    free(data);
    return IMAGE_FFMPEG_ERROR_ENCODE;
  }
  sws_freeContext(context);
  free(image->data);
  image->data = data;
  image->length = (uint32_t)length;
  image->width = destination_width;
  image->height = destination_height;
  image->stride = destination_width * 4u;
  return IMAGE_FFMPEG_OK;
}
#endif

IMAGE_FFMPEG_EXPORT int32_t image_ffmpeg_transcode_image(
    const uint8_t *input, uint32_t input_length,
    const image_ffmpeg_transcode_options *options,
    image_ffmpeg_encoded_image *output) {
  if (input == NULL || input_length == 0 || options == NULL || output == NULL) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
  memset(output, 0, sizeof(*output));
  if ((options->output_format != IMAGE_FFMPEG_IMAGE_FORMAT_JPEG &&
       options->output_format != IMAGE_FFMPEG_IMAGE_FORMAT_PNG) ||
      options->apply_orientation > 1 ||
      options->passthrough_if_unchanged > 1 ||
      ((options->crop_width == 0) != (options->crop_height == 0)) ||
      ((options->fill_width == 0) != (options->fill_height == 0)) ||
      options->jpeg_quality < 1 || options->jpeg_quality > 100 ||
      options->jpeg_chroma > IMAGE_FFMPEG_JPEG_CHROMA_444 ||
      options->png_compression_level > 9) {
    return IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT;
  }
#if defined(IMAGE_FFMPEG_WITH_FFMPEG)
  int32_t status;
  image_ffmpeg_image_info info;
  image_ffmpeg_image decoded;
  image_ffmpeg_buffer encoded;
  memset(&decoded, 0, sizeof(decoded));
  memset(&encoded, 0, sizeof(encoded));

  status = image_ffmpeg_probe_image(input, input_length, &info);
  if (status != IMAGE_FFMPEG_OK) goto cleanup;
  uint32_t source_width =
      options->apply_orientation ? info.display_width : info.width;
  uint32_t source_height =
      options->apply_orientation ? info.display_height : info.height;
  int no_crop = options->crop_width == 0;
  int no_fill = options->fill_width == 0;
  int no_resize =
      (options->max_width == 0 || source_width <= options->max_width) &&
      (options->max_height == 0 || source_height <= options->max_height);
  int orientation_unchanged =
      !options->apply_orientation ||
      info.orientation == IMAGE_FFMPEG_ORIENTATION_NORMAL;
  if (options->passthrough_if_unchanged && no_crop && no_fill && no_resize &&
      orientation_unchanged && info.format == options->output_format) {
    uint8_t *copy = (uint8_t *)malloc(input_length);
    if (copy == NULL) {
      status = IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY;
      goto cleanup;
    }
    memcpy(copy, input, input_length);
    output->data = copy;
    output->length = input_length;
    output->width = info.width;
    output->height = info.height;
    output->format = info.format;
    status = IMAGE_FFMPEG_OK;
    goto cleanup;
  }

  status = image_ffmpeg_decode_image_rgba(input, input_length, 0, 0, &decoded);
  if (status != IMAGE_FFMPEG_OK) goto cleanup;
  if (options->apply_orientation) {
    status = image_ffmpeg_orient_rgba(&decoded, info.orientation);
    if (status != IMAGE_FFMPEG_OK) goto cleanup;
  }
  status = image_ffmpeg_fill_rgba(
      &decoded, options->fill_x, options->fill_y, options->fill_width,
      options->fill_height, options->fill_argb);
  if (status != IMAGE_FFMPEG_OK) goto cleanup;
  status = image_ffmpeg_crop_rgba(
      &decoded, options->crop_x, options->crop_y, options->crop_width,
      options->crop_height);
  if (status != IMAGE_FFMPEG_OK) goto cleanup;
  status = image_ffmpeg_fit_rgba(&decoded, options->max_width,
                                options->max_height);
  if (status != IMAGE_FFMPEG_OK) goto cleanup;

  if (options->output_format == IMAGE_FFMPEG_IMAGE_FORMAT_JPEG) {
    status = image_ffmpeg_encode_jpeg_rgba_ex(
        decoded.data, decoded.length, decoded.width, decoded.height,
        decoded.stride, options->jpeg_quality, options->jpeg_chroma,
        options->jpeg_background_argb, &encoded);
  } else {
    status = image_ffmpeg_encode_png_rgba(
        decoded.data, decoded.length, decoded.width, decoded.height,
        decoded.stride, options->png_compression_level, &encoded);
  }
  if (status != IMAGE_FFMPEG_OK) goto cleanup;
  output->data = encoded.data;
  output->length = encoded.length;
  output->width = decoded.width;
  output->height = decoded.height;
  output->format = options->output_format;
  encoded.data = NULL;
  encoded.length = 0;
  status = IMAGE_FFMPEG_OK;

cleanup:
  image_ffmpeg_buffer_release(&encoded);
  image_ffmpeg_image_release(&decoded);
  return status;
#else
  return IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED;
#endif
}

IMAGE_FFMPEG_EXPORT void image_ffmpeg_image_release(image_ffmpeg_image *image) {
  if (image == NULL) return;
  free(image->data);
  memset(image, 0, sizeof(*image));
}

IMAGE_FFMPEG_EXPORT void image_ffmpeg_buffer_release(
    image_ffmpeg_buffer *buffer) {
  if (buffer == NULL) return;
  free(buffer->data);
  memset(buffer, 0, sizeof(*buffer));
}

IMAGE_FFMPEG_EXPORT void image_ffmpeg_encoded_image_release(
    image_ffmpeg_encoded_image *image) {
  if (image == NULL) return;
  free(image->data);
  memset(image, 0, sizeof(*image));
}

IMAGE_FFMPEG_EXPORT const char *image_ffmpeg_error_message(int32_t status) {
  switch (status) {
    case IMAGE_FFMPEG_OK:
      return "success";
    case IMAGE_FFMPEG_ERROR_INVALID_ARGUMENT:
      return "invalid argument";
    case IMAGE_FFMPEG_ERROR_FFMPEG_NOT_LINKED:
      return "FFmpeg is not linked into this build";
    case IMAGE_FFMPEG_ERROR_DECODE:
      return "recognized image data could not be decoded";
    case IMAGE_FFMPEG_ERROR_OUT_OF_MEMORY:
      return "out of memory";
    case IMAGE_FFMPEG_ERROR_UNSUPPORTED:
      return "image format or dimensions are unsupported by this build";
    case IMAGE_FFMPEG_ERROR_NOT_IMAGE:
      return "input is not a recognized image";
    case IMAGE_FFMPEG_ERROR_ENCODE:
      return "RGBA pixels could not be encoded";
    default:
      return "unknown image_ffmpeg error";
  }
}
