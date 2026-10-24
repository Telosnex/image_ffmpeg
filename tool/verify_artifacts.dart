/// Checks the upstream source pins and the build profile in
/// native_artifacts/manifest.json. The native libraries are in
/// native_artifacts/prebuilt.json and the web files in
/// native_artifacts/web.json; `dart run kiln:check` verifies both.
library;

import 'dart:convert';
import 'dart:io';

const _expectedSources = {
  'ffmpeg': 'd32b387f2b0a484599d4587d651891f0c63c4238',
  'libaom': '10aece4157eb79315da205f39e19bf6ab3ee30d0',
  'zlib': '51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf',
};

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final manifestFile = File('${root.path}/native_artifacts/manifest.json');
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map<String, Object?> ||
      decoded['schema'] != 1 ||
      decoded['profile'] != 9) {
    throw const FormatException('Unsupported artifact manifest/profile');
  }

  final sources = decoded['sources'];
  if (sources is! Map<String, Object?> ||
      sources.length != _expectedSources.length ||
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
  for (final key in const ['web', 'toolchains']) {
    if (decoded.containsKey(key)) {
      throw FormatException(
        '$key: the web files belong in native_artifacts/web.json '
        '(kiln ADR 002). kiln:check verifies them.',
      );
    }
  }
  stdout.writeln('OK sources and profile');
}
