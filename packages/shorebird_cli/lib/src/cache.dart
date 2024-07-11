// ignore_for_file: public_member_api_docs

import 'dart:io' hide Platform;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:retry/retry.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/checksum_checker.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

/// {@template cache_update_failure}
/// Thrown when a cache update fails.
/// This can occur if the artifact is unreachable or
/// if the download is interrupted.
/// {@endtemplate}
class CacheUpdateFailure implements Exception {
  /// {@macro cache_update_failure}
  const CacheUpdateFailure(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'CacheUpdateFailure: $message';
}

// A reference to a [Cache] instance.
final cacheRef = create(Cache.new);

// The [Cache] instance available in the current zone.
Cache get cache => read(cacheRef);

/// {@template cache}
/// A class that manages the artifacts cached by Shorebird.
/// This class handles fetching and unpacking artifacts from various sources.
///
/// To access specific artifacts, it's generally recommended to use
/// [ShorebirdArtifacts] since uses the current Shorebird environment.
/// {@endtemplate}
class Cache {
  Cache() {
    registerArtifact(PatchArtifact(cache: this, platform: platform));
    registerArtifact(BundleToolArtifact(cache: this, platform: platform));
    registerArtifact(AotToolsDillArtifact(cache: this, platform: platform));
  }

  void registerArtifact(CachedArtifact artifact) => _artifacts.add(artifact);

  Future<void> updateAll() async {
    for (final artifact in _artifacts) {
      if (await artifact.isValid()) {
        continue;
      }

      await retry(
        artifact.update,
        maxAttempts: 3,
        onRetry: (e) {
          logger
            ..detail('Failed to update ${artifact.fileName}, retrying...')
            ..detail(e.toString());
        },
      );
    }
  }

  /// Get a named directory from with the cache's artifact directory;
  /// for example, `foo` would return `bin/cache/artifacts/foo`.
  Directory getArtifactDirectory(String name) {
    return Directory(
      p.join(shorebirdArtifactsDirectory.path, p.withoutExtension(name)),
    );
  }

  /// Get a named directory from with the cache's preview directory;
  /// for example, `foo` would return `bin/cache/previews/foo`.
  Directory getPreviewDirectory(String name) {
    return Directory(
      p.join(shorebirdPreviewsDirectory.path, p.withoutExtension(name)),
    );
  }

  /// The Shorebird cache directory.
  static Directory get shorebirdCacheDirectory {
    return Directory(
      p.join(shorebirdEnv.shorebirdRoot.path, 'bin', 'cache'),
    );
  }

  /// The Shorebird cached previews directory.
  static Directory get shorebirdPreviewsDirectory {
    return Directory(
      p.join(shorebirdCacheDirectory.path, 'previews'),
    );
  }

  /// The Shorebird cached artifacts directory.
  static Directory get shorebirdArtifactsDirectory {
    return Directory(
      p.join(shorebirdCacheDirectory.path, 'artifacts'),
    );
  }

  final List<CachedArtifact> _artifacts = [];

  String get storageBaseUrl => 'https://storage.googleapis.com';

  String get storageBucket => 'download.shorebird.dev';

  Future<void> clear() async {
    final cacheDir = shorebirdCacheDirectory;
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
  }
}

abstract class CachedArtifact {
  CachedArtifact({required this.cache, required this.platform});

  final Cache cache;
  final Platform platform;

  /// The on-disk name of the artifact.
  String get fileName;

  /// Should the artifact be marked executable.
  bool get isExecutable;

  /// The URL from which the artifact can be downloaded.
  String get storageUrl;

  /// Whether the artifact is required for Shorebird to function.
  /// If we fail to fetch it we will exit with an error.
  bool get required => true;

  /// The SHA256 checksum of the artifact binary.
  ///
  /// When null, the checksum is not verified and the downloaded artifact
  /// is assumed to be correct.
  String? get checksum;

  Future<void> extractArtifact(http.ByteStream stream, String outputPath) {
    final file = File(p.join(outputPath, fileName))
      ..createSync(recursive: true);
    return stream.pipe(file.openWrite());
  }

  File get file =>
      File(p.join(cache.getArtifactDirectory(fileName).path, fileName));

  Future<bool> isValid() async {
    if (!file.existsSync()) {
      return false;
    }

    if (checksum == null) {
      logger.detail(
        '''No checksum provided for $fileName, skipping file corruption validation''',
      );
      return true;
    }

    return checksumChecker.checkFile(file, checksum!);
  }

  Future<void> update() async {
    final request = http.Request('GET', Uri.parse(storageUrl));
    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request);
    } catch (error) {
      throw CacheUpdateFailure(
        '''
Failed to download $fileName: $error
If you're behind a firewall/proxy, please, make sure shorebird_cli is
allowed to access $storageUrl.''',
      );
    }

    if (response.statusCode != HttpStatus.ok) {
      if (!required && response.statusCode == HttpStatus.notFound) {
        logger.detail(
          '[cache] optional artifact: "$fileName" was not found, skipping...',
        );
        return;
      }

      throw CacheUpdateFailure(
        '''Failed to download $fileName: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    final artifactDirectory = Directory(p.dirname(file.path));
    await extractArtifact(response.stream, artifactDirectory.path);

    final expectedChecksum = checksum;
    if (expectedChecksum != null) {
      if (!checksumChecker.checkFile(file, expectedChecksum)) {
        // Delete the artifact directory, so if the download is retried, it will
        // be re-downloaded.
        artifactDirectory.deleteSync(recursive: true);
        throw CacheUpdateFailure(
          '''Failed to download $fileName: checksum mismatch''',
        );
      } else {
        logger.detail(
          '''No checksum provided for $fileName, skipping file corruption validation''',
        );
      }
    }

    if (!platform.isWindows && isExecutable) {
      final result = await process.start('chmod', ['+x', file.path]);
      await result.exitCode;
    }
  }
}

class AotToolsDillArtifact extends CachedArtifact {
  AotToolsDillArtifact({required super.cache, required super.platform});

  @override
  String get fileName => 'aot-tools.dill';

  @override
  bool get isExecutable => false;

  /// The aot-tools are only available for revisions that support mixed-mode.
  @override
  bool get required => false;

  @override
  File get file => File(
        p.join(
          cache.getArtifactDirectory(fileName).path,
          shorebirdEnv.shorebirdEngineRevision,
          fileName,
        ),
      );

  @override
  String get storageUrl =>
      '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/${shorebirdEnv.shorebirdEngineRevision}/$fileName';

  @override
  String? get checksum => null;
}

class PatchArtifact extends CachedArtifact {
  PatchArtifact({required super.cache, required super.platform});

  @override
  String get fileName => 'patch';

  @override
  bool get isExecutable => true;

  @override
  Future<void> extractArtifact(
    http.ByteStream stream,
    String outputPath,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final artifactPath = p.join(tempDir.path, '$fileName.zip');
    await stream.pipe(File(artifactPath).openWrite());
    await artifactManager.extractZip(
      zipFile: File(artifactPath),
      outputDirectory: Directory(outputPath),
    );
  }

  @override
  String get storageUrl {
    var artifactName = 'patch-';
    if (platform.isMacOS) {
      artifactName += 'darwin-x64.zip';
    } else if (platform.isLinux) {
      artifactName += 'linux-x64.zip';
    } else if (platform.isWindows) {
      artifactName += 'windows-x64.zip';
    }

    return '${cache.storageBaseUrl}/${cache.storageBucket}/shorebird/${shorebirdEnv.shorebirdEngineRevision}/$artifactName';
  }

  @override
  String? get checksum => null;
}

class BundleToolArtifact extends CachedArtifact {
  BundleToolArtifact({required super.cache, required super.platform});

  @override
  String get fileName => 'bundletool.jar';

  @override
  bool get isExecutable => false;

  @override
  String get storageUrl {
    return 'https://github.com/google/bundletool/releases/download/1.15.6/bundletool-all-1.15.6.jar';
  }

  @override
  String? get checksum =>
      // SHA-256 checksum of the bundletool.jar file.
      // When updating the bundletool version, be sure to update this checksum.
      // This can be done by running the following command:
      // ```shell
      // shasum --algorithm 256 /path/to/file
      // ```
      '''38ae8a10bcdacef07ecce8211188c5c92b376be96da38ff3ee1f2cf4895b2cb8''';
}
