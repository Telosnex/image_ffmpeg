/// Builds the image_ffmpeg web runtime: the pinned libaom (AV1 decoder only)
/// and FFmpeg as Wasm libraries, then the shim as one Emscripten ES module,
/// image_ffmpeg_module.mjs and image_ffmpeg_module.wasm in --out.
///
/// The release workflow runs it in the pinned emscripten/emsdk:5.0.0 image
/// (native_prebuilt ADR 002 D10). For a local build, activate Emscripten
/// 5.0.0 or put it at ../emsdk, then install the files with
///
///     dart run tool/build_web.dart --out /tmp/image_ffmpeg_web
///     dart run native_prebuilt:web install-dev --from /tmp/image_ffmpeg_web
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

const _usage =
    'dart run tool/build_web.dart --out <dir> [--work <dir>]\n'
    '  --out   Directory for the two generated files.\n'
    '  --work  Directory for the libaom and FFmpeg builds. Default: build/.';

const _outputs = ['image_ffmpeg_module.mjs', 'image_ffmpeg_module.wasm'];
const _emscripten = '5.0.0 (a7c5deabd7c88ba1c38ebe988112256775f944c6)';

const _exportedFunctions = [
  '_malloc',
  '_free',
  '_image_ffmpeg_abi_version',
  '_image_ffmpeg_build_info',
  '_image_ffmpeg_has_ffmpeg',
  '_image_ffmpeg_probe_image',
  '_image_ffmpeg_decode_image_rgba',
  '_image_ffmpeg_decode_image_rgba_box_average',
  '_image_ffmpeg_encode_jpeg_rgba',
  '_image_ffmpeg_encode_png_rgba',
  '_image_ffmpeg_transcode_image',
  '_image_ffmpeg_image_release',
  '_image_ffmpeg_buffer_release',
  '_image_ffmpeg_encoded_image_release',
  '_image_ffmpeg_error_message',
];

const _aomHeaders = [
  'aom.h',
  'aom_codec.h',
  'aom_decoder.h',
  'aom_frame_buffer.h',
  'aom_image.h',
  'aom_integer.h',
  'aomdx.h',
];

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final root = Directory.fromUri(Platform.script.resolve('..')).absolute.path;
  final out = Directory(options['out']!).absolute;
  final work = Directory(options['work'] ?? '$root/build').absolute.path;
  if (await out.exists()) {
    await for (final entity in out.list()) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (!_outputs.contains(name)) _fail('--out holds other files: $name');
    }
  }
  await out.create(recursive: true);

  final emsdkEnv = await _emsdkEnvironment(root);
  final jobs =
      '${Platform.environment['IMAGE_FFMPEG_BUILD_JOBS'] ?? Platform.numberOfProcessors}';
  Future<void> run(
    List<String> command, {
    String? cwd,
    Map<String, String> env = const {},
  }) => _run(command, cwd: cwd ?? root, emsdkEnv: emsdkEnv, env: env);

  final version = await _output(['emcc', '--version'], root, emsdkEnv);
  if (!version.split('\n').first.contains(_emscripten)) {
    _fail(
      'Emscripten $_emscripten is required, found: ${version.split('\n').first}',
    );
  }

  await run(['bash', 'tool/fetch_aom.sh']);
  await run(['bash', 'tool/fetch_ffmpeg.sh']);

  // libaom: AV1 decoder only, no threads, no runtime CPU detection.
  final aomSource = '$root/third_party/aom';
  final aomBuild = '$work/aom-wasm';
  final aomPrefix = '$aomBuild/install';
  await Directory(aomBuild).create(recursive: true);
  await run([
    'emcmake',
    'cmake',
    '-S',
    aomSource,
    '-B',
    aomBuild,
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_INSTALL_PREFIX=$aomPrefix',
    '-DBUILD_SHARED_LIBS=OFF',
    '-DAOM_TARGET_CPU=generic',
    '-DENABLE_DOCS=OFF',
    '-DENABLE_EXAMPLES=OFF',
    '-DENABLE_TESTS=OFF',
    '-DENABLE_TOOLS=OFF',
    '-DCONFIG_AV1_DECODER=1',
    '-DCONFIG_AV1_ENCODER=0',
    '-DCONFIG_MULTITHREAD=0',
    '-DCONFIG_RUNTIME_CPU_DETECT=0',
    '-DCONFIG_WEBM_IO=0',
    '-DAOM_EXTRA_C_FLAGS=-O3',
    '-DAOM_EXTRA_CXX_FLAGS=-O3',
  ]);
  await run([
    'cmake',
    '--build',
    aomBuild,
    '--target',
    'aom',
    '--parallel',
    jobs,
  ]);
  // The decoder-only Emscripten configuration makes no aom.pc, so its install
  // target fails. Install the archive and the public decoder headers.
  await Directory('$aomPrefix/include/aom').create(recursive: true);
  await Directory('$aomPrefix/lib').create(recursive: true);
  await File('$aomBuild/libaom.a').copy('$aomPrefix/lib/libaom.a');
  for (final header in _aomHeaders) {
    await File('$aomSource/aom/$header').copy('$aomPrefix/include/aom/$header');
  }

  // FFmpeg: still-image decoders and the JPEG and PNG encoders.
  final ffmpegBuild = '$work/ffmpeg-wasm';
  final ffmpegPrefix = '$ffmpegBuild/install';
  await Directory(ffmpegBuild).create(recursive: true);
  final ffmpegEnv = {'AOM_PREFIX': aomPrefix};
  await run(
    [
      'emconfigure',
      '$root/third_party/ffmpeg/configure',
      '--prefix=$ffmpegPrefix',
      '--target-os=none',
      '--arch=x86_32',
      '--enable-cross-compile',
      '--cc=emcc',
      '--cxx=em++',
      '--objcc=emcc',
      '--dep-cc=emcc',
      '--ar=emar',
      '--ranlib=emranlib',
      '--nm=emnm',
      '--pkg-config=$root/tool/pkg_config_aom.sh',
      '--pkg-config-flags=--static',
      '--enable-static',
      '--disable-shared',
      '--disable-asm',
      '--disable-stripping',
      '--disable-programs',
      '--disable-doc',
      '--disable-debug',
      '--disable-runtime-cpudetect',
      '--disable-autodetect',
      '--disable-pthreads',
      '--disable-w32threads',
      '--disable-os2threads',
      '--disable-network',
      '--disable-iconv',
      '--disable-bzlib',
      '--disable-lzma',
      '--enable-zlib',
      '--disable-avdevice',
      '--disable-avfilter',
      '--enable-avformat',
      '--disable-swresample',
      '--disable-everything',
      '--enable-libaom',
      '--enable-decoder=mjpeg,png,apng,webp,webp_anim,gif,bmp,tiff,psd,libaom_av1',
      '--enable-encoder=mjpeg,png',
      '--enable-demuxer=image_jpeg_pipe,image_png_pipe,apng,image_webp_pipe,'
          'webp_anim,image_gif_pipe,image_bmp_pipe,image_tiff_pipe,'
          'image_psd_pipe,ico,mov',
      '--enable-small',
      '--extra-cflags=-O3 -sUSE_ZLIB=1',
      '--extra-ldflags=-sUSE_ZLIB=1',
    ],
    cwd: ffmpegBuild,
    env: ffmpegEnv,
  );
  await run(
    [
      'emmake',
      'make',
      '-j$jobs',
      'libavformat/libavformat.a',
      'libavcodec/libavcodec.a',
      'libavutil/libavutil.a',
      'libswscale/libswscale.a',
    ],
    cwd: ffmpegBuild,
    env: ffmpegEnv,
  );
  await run(
    ['emmake', 'make', 'install-libs', 'install-headers'],
    cwd: ffmpegBuild,
    env: ffmpegEnv,
  );

  await run([
    'emcc',
    '$root/src/image_ffmpeg.c',
    '-I$root/src',
    '-I$ffmpegPrefix/include',
    '-DIMAGE_FFMPEG_WITH_FFMPEG=1',
    '$ffmpegPrefix/lib/libavformat.a',
    '$ffmpegPrefix/lib/libavcodec.a',
    '$ffmpegPrefix/lib/libswscale.a',
    '$ffmpegPrefix/lib/libavutil.a',
    '$aomPrefix/lib/libaom.a',
    '-lm',
    '-O3',
    '--no-entry',
    '-sMODULARIZE=1',
    '-sEXPORT_ES6=1',
    '-sENVIRONMENT=web,worker,node',
    '-sALLOW_MEMORY_GROWTH=1',
    '-sFILESYSTEM=0',
    '-sUSE_ZLIB=1',
    '-sEXPORTED_FUNCTIONS=${_exportedFunctions.join(',')}',
    '-sEXPORTED_RUNTIME_METHODS=UTF8ToString,HEAPU8',
    '-o',
    '${out.path}/${_outputs.first}',
  ]);

  stdout.writeln('Built:');
  for (final name in _outputs) {
    final file = File('${out.path}/$name');
    if (!file.existsSync()) _fail('Expected output not found: ${file.path}');
    final bytes = await file.readAsBytes();
    stdout.writeln('  ${sha256.convert(bytes)}  ${bytes.length}  $name');
  }
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final name = switch (args[i]) {
      '-h' || '--help' => _exitHelp(),
      '--out' => 'out',
      '--work' => 'work',
      _ => _fail('Unknown argument: ${args[i]}\n$_usage'),
    };
    if (i + 1 == args.length) _fail('${args[i]} needs a value.\n$_usage');
    options[name] = args[++i];
  }
  if (options['out'] == null) _fail('Pass --out.\n$_usage');
  return options;
}

Never _exitHelp() {
  stdout.writeln(_usage);
  exit(0);
}

/// Null if the emcc on the PATH is the pinned version, else
/// ../emsdk/emsdk_env.sh, which each command then sources.
Future<String?> _emsdkEnvironment(String root) async {
  final probe = await Process.run('bash', ['-c', 'emcc --version']);
  if (probe.exitCode == 0 && '${probe.stdout}'.contains(_emscripten)) {
    return null;
  }
  final env = File('$root/../emsdk/emsdk_env.sh');
  if (env.existsSync()) return env.absolute.path;
  _fail(
    'Emscripten $_emscripten not found. Activate it, or put it at '
    '${env.parent.path}.',
  );
}

List<String> _wrap(List<String> command, String? emsdkEnv) => emsdkEnv == null
    ? command
    : [
        'bash',
        '-c',
        'source "\$0" > /dev/null && exec "\$@"',
        emsdkEnv,
        ...command,
      ];

Future<String> _output(
  List<String> command,
  String cwd,
  String? emsdkEnv,
) async {
  final c = _wrap(command, emsdkEnv);
  final result = await Process.run(
    c.first,
    c.skip(1).toList(),
    workingDirectory: cwd,
    environment: {if (emsdkEnv != null) 'EMSDK_QUIET': '1'},
  );
  if (result.exitCode != 0) {
    _fail('${command.join(' ')} failed: ${result.stderr}');
  }
  return '${result.stdout}';
}

Future<void> _run(
  List<String> command, {
  required String cwd,
  required String? emsdkEnv,
  Map<String, String> env = const {},
}) async {
  stdout.writeln('+ ${command.join(' ')}');
  final c = _wrap(command, emsdkEnv);
  final process = await Process.start(
    c.first,
    c.skip(1).toList(),
    workingDirectory: cwd,
    environment: {...env, if (emsdkEnv != null) 'EMSDK_QUIET': '1'},
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) _fail('${command.first} failed with exit code $code.');
}

Never _fail(String message) {
  stderr.writeln('build_web: $message');
  exit(1);
}
