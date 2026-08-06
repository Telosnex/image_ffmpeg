// Adapter around Emscripten's generated image_ffmpeg_module.mjs.
//
// This deliberately mirrors lib/src/backend/backend_native.dart: allocate and
// copy input, call the same C ABI once, copy output, then release C memory.
// It is intended to run inside image_ffmpeg_worker.mjs, not on the UI thread.

const ABI_VERSION = 4;
const IMAGE_STRUCT_SIZE = 24; // six wasm32 uint32 fields
const BUFFER_STRUCT_SIZE = 8; // wasm32 pointer + uint32 length
const INFO_STRUCT_SIZE = 32; // eight 32-bit fields
const TRANSCODE_OPTIONS_SIZE = 72; // eighteen uint32 fields
const ENCODED_IMAGE_STRUCT_SIZE = 20; // pointer + four uint32 fields

export async function createImageFfmpeg(moduleFactory) {
  const module = await moduleFactory();
  const abi = module._image_ffmpeg_abi_version();
  if (abi !== ABI_VERSION) {
    throw new Error(`image_ffmpeg ABI mismatch: expected ${ABI_VERSION}, got ${abi}`);
  }

  function encodeRgba(image, encoderOptions, encoder) {
    const input = module._malloc(image.bytes.byteLength);
    const output = module._malloc(BUFFER_STRUCT_SIZE);
    try {
      module.HEAPU8.set(image.bytes, input);
      module.HEAPU8.fill(0, output, output + BUFFER_STRUCT_SIZE);
      const status = encoder(
        input,
        image.bytes.byteLength,
        image.width,
        image.height,
        image.stride,
        ...encoderOptions,
        output,
      );
      if (status !== 0) {
        const message = module.UTF8ToString(
          module._image_ffmpeg_error_message(status),
        );
        throw Object.assign(new Error(message), {status});
      }
      const words = new Uint32Array(module.HEAPU8.buffer, output, 2);
      const [data, length] = words;
      return module.HEAPU8.slice(data, data + length);
    } finally {
      module._image_ffmpeg_buffer_release(output);
      module._free(output);
      module._free(input);
    }
  }

  return {
    abiVersion: abi,
    hasFfmpeg: module._image_ffmpeg_has_ffmpeg() !== 0,
    buildInfo: module.UTF8ToString(module._image_ffmpeg_build_info()),

    encodeJpeg(
      image,
      quality = 80,
      chroma = 0,
      backgroundColor = 0xffffffff,
    ) {
      return encodeRgba(
        image,
        [quality, chroma, backgroundColor],
        module._image_ffmpeg_encode_jpeg_rgba_ex,
      );
    },

    encodePng(image, compressionLevel = 6) {
      return encodeRgba(
        image,
        [compressionLevel],
        module._image_ffmpeg_encode_png_rgba,
      );
    },

    probeImage(encoded) {
      const input = module._malloc(encoded.byteLength);
      const output = module._malloc(INFO_STRUCT_SIZE);
      try {
        module.HEAPU8.set(encoded, input);
        module.HEAPU8.fill(0, output, output + INFO_STRUCT_SIZE);
        const status = module._image_ffmpeg_probe_image(
          input,
          encoded.byteLength,
          output,
        );
        if (status !== 0) {
          const message = module.UTF8ToString(
            module._image_ffmpeg_error_message(status),
          );
          throw Object.assign(new Error(message), {status});
        }
        const words = new Uint32Array(module.HEAPU8.buffer, output, 8);
        const signedWords = new Int32Array(module.HEAPU8.buffer, output, 8);
        const [format, width, height, displayWidth, displayHeight, orientation,
          frameCount] = words;
        return {
          format,
          width,
          height,
          displayWidth,
          displayHeight,
          orientation,
          frameCount,
          hasAlpha: signedWords[7],
        };
      } finally {
        module._free(output);
        module._free(input);
      }
    },

    transcodeImage(encoded, options) {
      const input = module._malloc(encoded.byteLength);
      const nativeOptions = module._malloc(TRANSCODE_OPTIONS_SIZE);
      const output = module._malloc(ENCODED_IMAGE_STRUCT_SIZE);
      try {
        module.HEAPU8.set(encoded, input);
        new Uint32Array(module.HEAPU8.buffer, nativeOptions, 18).set([
          options.outputFormat,
          options.maxWidth ?? 0,
          options.maxHeight ?? 0,
          options.applyOrientation === false ? 0 : 1,
          options.cropX ?? 0,
          options.cropY ?? 0,
          options.cropWidth ?? 0,
          options.cropHeight ?? 0,
          options.fillX ?? 0,
          options.fillY ?? 0,
          options.fillWidth ?? 0,
          options.fillHeight ?? 0,
          options.fillColor ?? 0,
          options.jpegQuality ?? 80,
          options.jpegChroma ?? 0,
          options.jpegBackgroundColor ?? 0xffffffff,
          options.pngCompressionLevel ?? 6,
          options.passthroughIfUnchanged ? 1 : 0,
        ]);
        module.HEAPU8.fill(
          0,
          output,
          output + ENCODED_IMAGE_STRUCT_SIZE,
        );
        const status = module._image_ffmpeg_transcode_image(
          input,
          encoded.byteLength,
          nativeOptions,
          output,
        );
        if (status !== 0) {
          const message = module.UTF8ToString(
            module._image_ffmpeg_error_message(status),
          );
          throw Object.assign(new Error(message), {status});
        }
        const words = new Uint32Array(module.HEAPU8.buffer, output, 5);
        const [data, length, width, height, format] = words;
        return {
          bytes: module.HEAPU8.slice(data, data + length),
          width,
          height,
          format,
        };
      } finally {
        module._image_ffmpeg_encoded_image_release(output);
        module._free(output);
        module._free(nativeOptions);
        module._free(input);
      }
    },

    decodeImage(encoded, maxWidth = 0, maxHeight = 0) {
      const input = module._malloc(encoded.byteLength);
      const output = module._malloc(IMAGE_STRUCT_SIZE);
      try {
        module.HEAPU8.set(encoded, input);
        module.HEAPU8.fill(0, output, output + IMAGE_STRUCT_SIZE);
        const status = module._image_ffmpeg_decode_image_rgba(
          input,
          encoded.byteLength,
          maxWidth,
          maxHeight,
          output,
        );
        if (status !== 0) {
          const message = module.UTF8ToString(
            module._image_ffmpeg_error_message(status),
          );
          throw Object.assign(new Error(message), {status});
        }

        const words = new Uint32Array(module.HEAPU8.buffer, output, 6);
        const [data, length, width, height, stride, pixelFormat] = words;
        // Copy out of growable Wasm linear memory before releasing the image.
        const bytes = module.HEAPU8.slice(data, data + length);
        return {bytes, width, height, stride, pixelFormat};
      } finally {
        module._image_ffmpeg_image_release(output);
        module._free(output);
        module._free(input);
      }
    },

    decodeImageBoxAverage(encoded, maxDimension, alphaMode = 0) {
      const input = module._malloc(encoded.byteLength);
      const output = module._malloc(IMAGE_STRUCT_SIZE);
      try {
        module.HEAPU8.set(encoded, input);
        module.HEAPU8.fill(0, output, output + IMAGE_STRUCT_SIZE);
        const status = module._image_ffmpeg_decode_image_rgba_box_average(
          input,
          encoded.byteLength,
          maxDimension,
          alphaMode,
          output,
        );
        if (status !== 0) {
          const message = module.UTF8ToString(
            module._image_ffmpeg_error_message(status),
          );
          throw Object.assign(new Error(message), {status});
        }

        const words = new Uint32Array(module.HEAPU8.buffer, output, 6);
        const [data, length, width, height, stride, pixelFormat] = words;
        const bytes = module.HEAPU8.slice(data, data + length);
        return {bytes, width, height, stride, pixelFormat};
      } finally {
        module._image_ffmpeg_image_release(output);
        module._free(output);
        module._free(input);
      }
    },
  };
}
