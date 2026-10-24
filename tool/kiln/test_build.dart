/// Runs after each native build of the kiln release workflow: the ABI
/// boundary test of tool/support/abi_boundary_test.c against the built
/// library, on macos-arm64 and linux-x64. On linux-x64 it also prints the
/// newest glibc requirement.
library;

import 'dart:io';

Future<void> main() async {
  final env = Platform.environment;
  final target = env['TARGET']!;
  final dir = '${env['OUT']}/out/$target';
  final test = '${env['RUNNER_TEMP']}/abi_boundary_test';

  switch (target) {
    case 'macos-arm64':
      await _run('xcrun', [
        '--sdk',
        'macosx',
        'clang',
        '-std=c11',
        '-O2',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-arch',
        'arm64',
        '-mmacosx-version-min=12',
        '-Isrc',
        'tool/support/abi_boundary_test.c',
        '$dir/libimage_ffmpeg.dylib',
        '-Wl,-rpath,$dir',
        '-o',
        test,
      ]);
    case 'linux-x64':
      await _run('gcc', [
        '-std=c11',
        '-O2',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-Isrc',
        'tool/support/abi_boundary_test.c',
        '-L$dir',
        '-limage_ffmpeg',
        '-pthread',
        '-Wl,-rpath,$dir',
        '-o',
        test,
      ]);
    default:
      return;
  }
  await _run(test, ['--quick']);

  if (target == 'linux-x64') {
    final symbols = await _run('objdump', [
      '-T',
      '$dir/libimage_ffmpeg.so',
    ], quiet: true);
    final versions = {
      for (final m in RegExp(r'GLIBC_([0-9.]+)').allMatches(symbols)) m[1]!,
    }.toList()..sort(_compareVersions);
    stdout.writeln('Newest glibc requirement: ${versions.last}');
  }
}

int _compareVersions(String a, String b) {
  final (x, y) = (
    a.split('.').map(int.parse).toList(),
    b.split('.').map(int.parse).toList(),
  );
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

Future<String> _run(
  String executable,
  List<String> args, {
  bool quiet = false,
}) async {
  if (!quiet) stdout.writeln('+ $executable ${args.join(' ')}');
  final result = await Process.run(executable, args);
  if (!quiet) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    stderr.writeln('$executable: exit ${result.exitCode}');
    exit(result.exitCode);
  }
  return '${result.stdout}';
}
