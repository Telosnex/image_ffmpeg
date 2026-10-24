// The query of this Worker URL holds the webVersion of the package
// (kiln ADR 002 D7). The adapter, generated module, and Wasm
// binary load with the same query, so a browser does not combine files of
// different versions.
const assetVersion = new URL(import.meta.url).search;

// Messages that arrive while the imports below load have no handler yet.
// Keep them, and dispatch them again at the end of this module.
const earlyMessages = [];
self.onmessage = ({data}) => earlyMessages.push(data);

function versionedSibling(path) {
  const url = new URL(path, import.meta.url);
  url.search = assetVersion;
  return url.href;
}

const [moduleImport, loaderImport] = await Promise.all([
  import(versionedSibling('./image_ffmpeg_module.mjs')),
  import(versionedSibling('./image_ffmpeg_loader.mjs')),
]);
const generatedCreateModule = moduleImport.default;
const {createImageFfmpeg} = loaderImport;

function createModule(options = {}) {
  return generatedCreateModule({
    ...options,
    // Emscripten resolves the Wasm binary itself, outside the JavaScript
    // module graph. Carry the same cache key onto that fetch as well.
    locateFile(path, prefix) {
      const located = options.locateFile
        ? options.locateFile(path, prefix)
        : new URL(path, import.meta.url).href;
      const url = new URL(located, import.meta.url);
      url.search = assetVersion;
      return url.href;
    },
  });
}

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
    if (operation === 'resourceUrls') {
      // For the browser test of the ?v= query on every loaded file.
      self.postMessage({
        id,
        result: performance.getEntriesByType('resource').map((e) => e.name),
      });
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

for (const data of earlyMessages.splice(0)) {
  self.dispatchEvent(new MessageEvent('message', {data}));
}
