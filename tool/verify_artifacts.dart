import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _expectedSources = {
  'ffmpeg': 'd32b387f2b0a484599d4587d651891f0c63c4238',
  'libaom': '10aece4157eb79315da205f39e19bf6ab3ee30d0',
  'zlib': '51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf',
};

const _webAssets = {'loader', 'worker', 'module', 'wasm'};

/// Verifies the source pins and the four committed Web assets. The native
/// libraries are in native_artifacts/prebuilt.json; check them with
/// `dart run native_prebuilt:check`.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final manifestFile = File('${root.path}/native_artifacts/manifest.json');
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map<String, Object?> ||
      decoded['schema'] != 1 ||
      decoded['profile'] != 9) {
    throw const FormatException('Unsupported artifact manifest/profile');
  }

  final sources = _stringObjectMap(decoded['sources'], 'sources');
  if (sources.length != _expectedSources.length ||
      _expectedSources.entries.any(
        (entry) => sources[entry.key] != entry.value,
      )) {
    throw const FormatException('Unexpected production source pins');
  }

  if (decoded.containsKey('artifacts')) {
    throw const FormatException(
      'Native libraries belong in native_artifacts/prebuilt.json',
    );
  }
  final web = _stringObjectMap(decoded['web'], 'web');
  _expectExactKeys(web.keys.toSet(), _webAssets, 'web asset');
  await _verifyEntries(root, web);
}

Future<void> _verifyEntries(
  Directory root,
  Map<String, Object?> entries,
) async {
  for (final entry in entries.entries) {
    final item = _stringObjectMap(entry.value, entry.key);
    final relativePath = item['path'];
    final expectedHash = item['sha256'];
    if (relativePath is! String ||
        expectedHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
      throw FormatException('Invalid manifest record: ${entry.key}');
    }
    final file = File('${root.path}/$relativePath');
    if (!await file.exists()) {
      throw StateError('Missing artifact: $relativePath');
    }
    final actualHash = sha256.convert(await file.readAsBytes()).toString();
    if (actualHash != expectedHash) {
      throw StateError(
        'Hash mismatch for ${entry.key}: expected $expectedHash, got $actualHash',
      );
    }
    stdout.writeln('${entry.key}: $actualHash (${await file.length()} bytes)');
  }
}

Map<String, Object?> _stringObjectMap(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

void _expectExactKeys(Set<String> actual, Set<String> expected, String label) {
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException(
      'Unexpected $label set: expected ${expected.toList()..sort()}, '
      'got ${actual.toList()..sort()}',
    );
  }
}
