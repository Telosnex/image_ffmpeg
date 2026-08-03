import {readFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';

import createModule from '../web/image_ffmpeg_module.mjs';
import {createImageFfmpeg} from '../web/image_ffmpeg_loader.mjs';

const defaultInput =
  '/Users/jpo/Documents/Telosnex/wallpaper/' +
  '019fbf46-5f54-7c0e-bef2-7dd87a5700a3.png';
const input = new Uint8Array(await readFile(process.argv[2] ?? defaultInput));
const ffmpeg = await createImageFfmpeg(createModule);
console.log({
  abiVersion: ffmpeg.abiVersion,
  hasFfmpeg: ffmpeg.hasFfmpeg,
  buildInfo: ffmpeg.buildInfo,
});
if (!ffmpeg.hasFfmpeg) {
  throw new Error('Build reduced FFmpeg and rerun tool/build_web.sh first');
}

for (let i = 0; i < 3; i++) ffmpeg.decodeImage(input, 96, 96);

const runs = [];
let image;
for (let i = 0; i < 10; i++) {
  const start = performance.now();
  image = ffmpeg.decodeImage(input, 96, 96);
  runs.push(performance.now() - start);
}
runs.sort((left, right) => left - right);
const mean = runs.reduce((sum, value) => sum + value, 0) / runs.length;
console.log(
  `Output: ${image.width}x${image.height}, ${image.bytes.length} RGBA bytes`,
);
console.log(`Runs (ms): ${runs.map((value) => value.toFixed(3)).join(', ')}`);
console.log(`Min (ms): ${runs[0].toFixed(3)}`);
console.log(`Median (ms): ${runs[Math.floor(runs.length / 2)].toFixed(3)}`);
console.log(`Mean (ms): ${mean.toFixed(3)}`);
