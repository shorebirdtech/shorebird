// ignore_for_file: public_member_api_docs

import 'dart:io' hide Platform;

import 'package:collection/collection.dart';
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
    registerArtifact(AotToolsArtifact(cache: this, platform: platform));
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
  String? get sha256Checksum;

  File get file =>
      File(p.join(cache.getArtifactDirectory(fileName).path, fileName));

  Future<bool> isValid() async {
    if (!file.existsSync()) {
      return false;
    }

    final expectedChecksum = sha256Checksum;
    if (expectedChecksum == null) {
      logger.detail(
        '''No checksum provided for $fileName, skipping file corruption validation''',
      );
      return true;
    }

    return checksumChecker.checkFile(
      file,
      checksum: expectedChecksum,
      algorithm: ChecksumAlgorithm.sha256,
    );
  }

  Future<void> update() async {
    try {
      final response = await _makeDownloadRequest();
      final tempFile = await _downloadFile(response);

      final isZip =
          response.headers[HttpHeaders.contentTypeHeader] == 'application/zip';

      _verifyChecksum(file: tempFile, responseHeaders: response.headers);

      // Create the directory containing the artifact if it does not already
      // exist. Failing to do this will cause [renameSync] to throw an exception.
      Directory(p.dirname(file.path)).createSync(recursive: true);

      if (isZip) {
        final unzipDirectory = Directory(
          p.join(p.dirname(tempFile.path), fileName),
        );
        await artifactManager.extractZip(
          zipFile: tempFile,
          outputDirectory: unzipDirectory,
        );
        unzipDirectory.renameSync(p.dirname(file.path));
      } else {
        tempFile.renameSync(file.path);
      }

      if (!platform.isWindows && isExecutable) {
        final result = await process.start('chmod', ['+x', file.path]);
        await result.exitCode;
      }
    } catch (e) {
      // Delete the location, so if the download is retried, it will be
      // re-downloaded.
      final artifactDirectory = Directory(p.dirname(file.path));
      if (artifactDirectory.existsSync()) {
        artifactDirectory.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  Future<http.StreamedResponse> _makeDownloadRequest() async {
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
        return response;
      }

      throw CacheUpdateFailure(
        '''Failed to download $fileName: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    return response;
  }

  Future<File> _downloadFile(http.StreamedResponse response) async {
    final isZip =
        response.headers[HttpHeaders.contentTypeHeader] == 'application/zip';
    final tempDirectory = Directory.systemTemp.createTempSync();
    final tempFile = File(
      p.join(tempDirectory.path, '$fileName${isZip ? '.zip' : ''}'),
    );
    await response.stream.pipe(tempFile.openWrite());
    return tempFile;
  }

  void _verifyChecksum({
    required File file,
    required Map<String, String> responseHeaders,
  }) {
    final String expectedChecksum;
    final ChecksumAlgorithm algorithm;
    if (sha256Checksum != null) {
      expectedChecksum = sha256Checksum!;
      algorithm = ChecksumAlgorithm.sha256;
    } else if (_gcpCrc32cChecksum(responseHeaders: responseHeaders) != null) {
      expectedChecksum = _gcpCrc32cChecksum(responseHeaders: responseHeaders)!;
      algorithm = ChecksumAlgorithm.crc32c;
    } else {
      return;
    }

    final isChecksumValid = checksumChecker.checkFile(
      file,
      checksum: expectedChecksum,
      algorithm: algorithm,
    );
    if (!isChecksumValid) {
      throw CacheUpdateFailure(
        '''Failed to download $fileName: checksum mismatch''',
      );
    }
  }

  String? _gcpCrc32cChecksum({required Map<String, String> responseHeaders}) {
    return responseHeaders['x-goog-hash']
        ?.split(',')
        .firstWhereOrNull(
          (header) => header.startsWith('crc32c='),
        )
        ?.replaceAll('crc32c=', '');
  }
}

class AotToolsArtifact extends CachedArtifact {
  AotToolsArtifact({required super.cache, required super.platform});

  @override
  String get fileName => 'aot-tools.dill';

  @override
  bool get isExecutable => false;

  /// The aot-tools are only available for revisions that support mixed-mode.
  /// Although this artifact is only used for iOS, it will be updated by
  /// [cache.updateAll()].
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
  String? get sha256Checksum => null;
}

class PatchArtifact extends CachedArtifact {
  PatchArtifact({required super.cache, required super.platform});

  @override
  String get fileName => 'patch';

  @override
  bool get isExecutable => true;

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
  String? get sha256Checksum => null;
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
  String? get sha256Checksum =>
      // SHA-256 checksum of the bundletool.jar file.
      // When updating the bundletool version, be sure to update this checksum.
      // This can be done by running the following command:
      // ```shell
      // shasum --algorithm 256 /path/to/file
      // ```
      // TODO(bryanoltman): github includes `content-md5` in the response
      // headers. There are tradeoffs to consider, but getting the checksum
      // from the response header would be more consistent with how we handle
      // GCP artifacts and would avoid the need to update this checksum
      // manually.
      '''38ae8a10bcdacef07ecce8211188c5c92b376be96da38ff3ee1f2cf4895b2cb8''';
}
