import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final manifestFile = File('native_artifacts/manifest.json');
  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest case {
    'schema': 1,
    'artifacts': final Map<String, Object?> artifacts,
  }) {
    for (final entry in artifacts.entries) {
      if (entry.value case {
        'path': final String path,
        'sha256': final String expected,
      }) {
        final artifact = File('native_artifacts/$path');
        if (!await artifact.exists()) {
          throw StateError('${entry.key}: missing ${artifact.path}');
        }
        final actual = (await sha256.bind(artifact.openRead()).first)
            .toString();
        if (actual != expected) {
          throw StateError(
            '${entry.key}: expected SHA-256 $expected, got $actual',
          );
        }
        stdout.writeln(
          '${entry.key}: $actual (${await artifact.length()} bytes)',
        );
        continue;
      }
      throw FormatException('Invalid artifact entry ${entry.key}.');
    }
    stdout.writeln('Verified ${artifacts.length} native artifacts.');
    return;
  }
  throw const FormatException('Invalid native_artifacts/manifest.json.');
}
