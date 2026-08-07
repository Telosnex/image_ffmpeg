import createModule from './image_ffmpeg_module.mjs';
import {createImageFfmpeg} from './image_ffmpeg_loader.mjs';

let runtimePromise;

function getRuntime() {
  return runtimePromise ??= createImageFfmpeg(createModule);
}

self.onmessage = async ({data}) => {
  const {id, operation} = data;
  try {
    const runtime = await getRuntime();
    if (operation === 'capabilities') {
      self.postMessage({
        id,
        result: {
          abiVersion: runtime.abiVersion,
          hasFfmpeg: runtime.hasFfmpeg,
          buildInfo: runtime.buildInfo,
        },
      });
      return;
    }
    if (operation === 'encodeJpeg' || operation === 'encodePng') {
      const image = {
        bytes: new Uint8Array(data.bytes),
        width: data.width,
        height: data.height,
        stride: data.stride,
      };
      const bytes = operation === 'encodeJpeg'
        ? runtime.encodeJpeg(
            image,
            data.quality,
            data.chroma,
            data.backgroundColor,
          )
        : runtime.encodePng(image, data.compressionLevel);
      self.postMessage({id, result: {bytes}}, [bytes.buffer]);
      return;
    }
    if (operation === 'probeImage') {
      const result = runtime.probeImage(new Uint8Array(data.encoded));
      self.postMessage({id, result});
      return;
    }
    if (operation === 'transcodeImage') {
      const result = runtime.transcodeImage(
        new Uint8Array(data.encoded),
        data.options,
      );
      self.postMessage({id, result}, [result.bytes.buffer]);
      return;
    }
    if (operation === 'decodeImage') {
      const result = runtime.decodeImage(
        new Uint8Array(data.encoded),
        data.maxWidth,
        data.maxHeight,
      );
      self.postMessage({id, result}, [result.bytes.buffer]);
      return;
    }
    if (operation === 'decodeImageBoxAverage') {
      const result = runtime.decodeImageBoxAverage(
        new Uint8Array(data.encoded),
        data.maxDimension,
        data.alphaMode,
      );
      self.postMessage({id, result}, [result.bytes.buffer]);
      return;
    }
    throw new Error(`Unknown image_ffmpeg operation: ${operation}`);
  } catch (error) {
    self.postMessage({
      id,
      error: {
        status: error.status ?? -1,
        message: error.message ?? String(error),
      },
    });
  }
};
