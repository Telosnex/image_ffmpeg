const overlapChannel = new BroadcastChannel('image_ffmpeg_pool_test');
let activeMarker = null;
let sawOverlap = false;

function markerOf(bytes) {
  return Array.from(bytes.slice(2)).join(',');
}

overlapChannel.onmessage = ({data}) => {
  if (activeMarker !== null && data === activeMarker) {
    sawOverlap = true;
  }
};

self.onmessage = ({data}) => {
  const {id, operation} = data;
  if (operation === 'capabilities') {
    self.postMessage({
      id,
      result: {
        abiVersion: 4,
        hasFfmpeg: true,
        buildInfo: 'image_ffmpeg pool test Worker',
      },
    });
    return;
  }
  if (operation !== 'probeImage') {
    self.postMessage({id, error: {status: -1, message: 'unsupported test operation'}});
    return;
  }

  const bytes = new Uint8Array(data.encoded);
  const delay = bytes[0];
  const value = bytes[1];
  if (delay === 254) {
    self.postMessage({id, error: {status: -6, message: 'forced FFmpeg error'}});
    return;
  }
  if (delay === 255) {
    setTimeout(() => {
      throw new Error('forced Worker failure');
    }, 0);
    return;
  }

  activeMarker = markerOf(bytes);
  sawOverlap = false;
  overlapChannel.postMessage(activeMarker);
  setTimeout(() => {
    const width = sawOverlap ? 2 : value;
    activeMarker = null;
    self.postMessage({
      id,
      result: {
        format: 2,
        width,
        height: 1,
        displayWidth: width,
        displayHeight: 1,
        orientation: 1,
        frameCount: 1,
        hasAlpha: 0,
      },
    });
  }, delay);
};
