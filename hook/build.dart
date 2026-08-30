import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _assetName = 'image_ffmpeg_bindings_generated.dart';

final class _Artifact {
  const _Artifact({required this.path, required this.sha256});

  factory _Artifact.fromJson(Object? value, String key) {
    if (value case {'path': final String path, 'sha256': final String sha256}) {
      if (sha256.length == 64) return _Artifact(path: path, sha256: sha256);
    }
    throw FormatException('Invalid native artifact manifest entry for $key.');
  }

  final String path;
  final String sha256;
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final hookStopwatch = Stopwatch()..start();
    final resolveAndVerifyStopwatch = Stopwatch()..start();
    final manifestFile = File.fromUri(
      input.packageRoot.resolve('native_artifacts/manifest.json'),
    );
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map<String, Object?> || manifest['schema'] != 1) {
      throw const FormatException('Unsupported native artifact manifest.');
    }
    final encodedArtifacts = manifest['artifacts'];
    if (encodedArtifacts is! Map<String, Object?>) {
      throw const FormatException('Native artifact manifest has no artifacts.');
    }

    final os = input.config.code.targetOS;
    final architecture = input.config.code.targetArchitecture;
    final sdkSuffix = os == OS.iOS
        ? switch (input.config.code.iOS.targetSdk) {
            IOSSdk.iPhoneOS => '-iphoneos',
            IOSSdk.iPhoneSimulator => '-iphonesimulator',
            final sdk => throw UnsupportedError('Unsupported iOS SDK: $sdk.'),
          }
        : '';
    final key = '${os.name}-${architecture.name}$sdkSuffix';
    final encodedArtifact = encodedArtifacts[key];
    if (encodedArtifact == null) {
      throw UnsupportedError(
        'image_ffmpeg has no pinned native artifact for $key. Supported '
        'targets: ${encodedArtifacts.keys.join(', ')}.',
      );
    }
    final artifact = _Artifact.fromJson(encodedArtifact, key);

    final source = File.fromUri(
      input.packageRoot.resolve('native_artifacts/${artifact.path}'),
    );
    if (!await source.exists()) {
      throw StateError(
        'Pinned image_ffmpeg artifact is missing: ${source.path}. Reinstall the '
        'package or rebuild it with tool/build_native_artifact.sh $key.',
      );
    }
    final digest = (await sha256.bind(source.openRead()).first).toString();
    if (digest != artifact.sha256) {
      throw StateError(
        'SHA-256 mismatch for ${source.path}: expected ${artifact.sha256}, '
        'got $digest.',
      );
    }
    final resolveAndVerifyDuration = resolveAndVerifyStopwatch.elapsed;

    final publishStopwatch = Stopwatch()..start();
    final outputDirectory = Directory.fromUri(input.outputDirectory);
    await outputDirectory.create(recursive: true);
    final outputName = os.dylibFileName('image_ffmpeg');
    final published = File.fromUri(input.outputDirectory.resolve(outputName));
    await source.copy(published.path);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: published.uri,
      ),
    );
    output.dependencies.addAll([
      input.packageRoot.resolve('hook/build.dart'),
      manifestFile.uri,
      source.uri,
    ]);
    final publishDuration = publishStopwatch.elapsed;

    // hooks_runner adds the terminating newline while capturing this chunk.
    stderr.write(
      '[image_ffmpeg] Hook completed in '
      '${_formatDuration(hookStopwatch.elapsed)} '
      '(resolve/verify ${_formatDuration(resolveAndVerifyDuration)}, '
      'publish/register ${_formatDuration(publishDuration)})',
    );
  });
}

String _formatDuration(Duration duration) {
  final millis = duration.inMilliseconds;
  if (millis < 1000) return '${millis}ms';
  final seconds = duration.inSeconds;
  final remainderMillis = millis - seconds * 1000;
  if (seconds < 60) {
    return '$seconds.${(remainderMillis ~/ 100).toString()}s';
  }
  final minutes = seconds ~/ 60;
  final remainderSeconds = seconds % 60;
  return '${minutes}m ${remainderSeconds}s';
}
