import 'dart:io' hide Platform;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/engine_revision.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';

class Cache {
  Cache({Platform platform = const LocalPlatform()}) {
    registerArtifact(PatchArtifact(cache: this, platform: platform));
  }

  void registerArtifact(CachedArtifact artifact) => _artifacts.add(artifact);

  Future<void> updateAll() async {
    for (final artifact in _artifacts) {
      if (await artifact.isUpToDate()) {
        continue;
      }

      await artifact.download();
    }
  }

  /// Get a named directory from with the cache's artifact directory;
  /// for example, `foo` would return `bin/cache/artifacts/foo`.
  Directory getArtifactDirectory(String name) {
    return Directory(p.join(shorebirdArtifactsDirectory.path, name));
  }

  /// The Shorebird cached artifacts directory.
  static Directory get shorebirdArtifactsDirectory => Directory(
        p.join(
          ShorebirdEnvironment.shorebirdCacheDirectory.path,
          'artifacts',
        ),
      );

  final List<CachedArtifact> _artifacts = [];

  String get storageBaseUrl => 'https://storage.googleapis.com';

  String get storageBucket => 'download.shorebird.dev';
}

abstract class CachedArtifact {
  CachedArtifact({required this.cache, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final Cache cache;
  final http.Client _httpClient;

  String get name;

  String get storagePath;

  List<String> get executables => [];

  Directory get location => cache.getArtifactDirectory(name);

  Future<bool> isUpToDate() async => location.existsSync();

  Future<void> download() async {
    final url = '${cache.storageBaseUrl}/${cache.storageBucket}/$storagePath';
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);
    final tempDir = Directory.systemTemp.createTempSync();
    final archivePath = p.join(tempDir.path, '$name.zip');
    await response.stream.pipe(File(archivePath).openWrite());

    await Isolate.run(
      () async {
        final inputStream = InputFileStream(archivePath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        extractArchiveToDisk(archive, location.path);
      },
    );

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
  PatchArtifact({required super.cache, required this.platform});

  final Platform platform;

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

    return 'shorebird/$shorebirdEngineRevision/$artifactName';
  }
}
