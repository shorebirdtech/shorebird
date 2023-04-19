import 'dart:io' hide Platform;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

typedef ArchiveExtracter = Future<void> Function(
  String archivePath,
  String outputPath,
);

Future<void> _defaultArchiveExtractor(String archivePath, String outputPath) {
  return Isolate.run(() {
    final inputStream = InputFileStream(archivePath);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    extractArchiveToDisk(archive, outputPath);
  });
}

class Cache {
  Cache({
    http.Client? httpClient,
    this.extractArchive = _defaultArchiveExtractor,
    Platform platform = const LocalPlatform(),
  }) : httpClient = httpClient ?? http.Client() {
    registerArtifact(PatchArtifact(cache: this, platform: platform));
  }

  final http.Client httpClient;
  final ArchiveExtracter extractArchive;

  void registerArtifact(CachedArtifact artifact) => _artifacts.add(artifact);

  Future<void> updateAll() async {
    for (final artifact in _artifacts) {
      if (await artifact.isUpToDate()) {
        continue;
      }

      await artifact.update();
    }
  }

  /// Get a named directory from with the cache's artifact directory;
  /// for example, `foo` would return `bin/cache/artifacts/foo`.
  Directory getArtifactDirectory(String name) {
    return Directory(p.join(shorebirdArtifactsDirectory.path, name));
  }

  /// The Shorebird cache directory.
  static Directory get shorebirdCacheDirectory {
    return Directory(
      p.join(ShorebirdEnvironment.shorebirdRoot.path, 'bin', 'cache'),
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

  void clear() {
    final cacheDir = shorebirdCacheDirectory;
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
  }
}

abstract class CachedArtifact {
  CachedArtifact({required this.cache, required this.platform});

  final Cache cache;
  final Platform platform;

  String get name;

  String get storagePath;

  List<String> get executables => [];

  Directory get location => cache.getArtifactDirectory(name);

  Future<bool> isUpToDate() async => location.existsSync();

  Future<void> update() async {
    final url = '${cache.storageBaseUrl}/${cache.storageBucket}/$storagePath';
    final request = http.Request('GET', Uri.parse(url));
    final response = await cache.httpClient.send(request);
    final tempDir = Directory.systemTemp.createTempSync();
    final archivePath = p.join(tempDir.path, '$name.zip');
    final outputPath = location.path;
    await response.stream.pipe(File(archivePath).openWrite());
    await cache.extractArchive(archivePath, outputPath);

    if (platform.isWindows) return;

    for (final executable in executables) {
      final process = await Process.start(
        'chmod',
        ['+x', p.join(location.path, executable)],
      );
      await process.exitCode;
    }
  }
}

class PatchArtifact extends CachedArtifact {
  PatchArtifact({required super.cache, required super.platform});

  @override
  String get name => 'patch';

  @override
  List<String> get executables => ['patch'];

  @override
  String get storagePath {
    var artifactName = 'patch-';
    if (platform.isMacOS) {
      artifactName += 'darwin-x64.zip';
    } else if (platform.isLinux) {
      artifactName += 'linux-x64.zip';
    } else if (platform.isWindows) {
      artifactName += 'windows-x64.zip';
    }

    return 'shorebird/${ShorebirdEnvironment.shorebirdEngineRevision}/$artifactName';
  }
}
