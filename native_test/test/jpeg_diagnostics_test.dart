import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'full-range JPEG scaling emits no deprecated pixel-format warning',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/decode_jpeg_diagnostics.dart',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('96x96'));
      expect(
        result.stderr,
        isNot(contains('deprecated pixel format used')),
        reason: 'YUVJ input must be normalized before creating SwsContext.',
      );
    },
  );
}
