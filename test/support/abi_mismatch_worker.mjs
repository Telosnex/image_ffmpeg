self.onmessage = ({data}) => {
  self.postMessage({
    id: data.id,
    result: {
      abiVersion: 3,
      hasFfmpeg: true,
      buildInfo: 'image_ffmpeg ABI mismatch test Worker',
    },
  });
};
