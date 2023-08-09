import 'dart:io' hide Platform;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

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

// A reference to a [Cache] instance.
final cacheRef = create(Cache.new);

// The [Cache] instance available in the current zone.
Cache get cache => read(cacheRef);

class Cache {
  Cache({
    http.Client? httpClient,
    this.extractArchive = _defaultArchiveExtractor,
  }) : httpClient = httpClient ?? retryingHttpClient(http.Client()) {
    registerArtifact(PatchArtifact(cache: this, platform: platform));
    registerArtifact(BundleToolArtifact(cache: this, platform: platform));
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

  String get storageUrl;

  List<String> get executables => [];

  Future<void> extractArtifact(http.ByteStream stream, String outputPath) {
    final file = File(p.join(outputPath, name))..createSync(recursive: true);
    return stream.pipe(file.openWrite());
  }

  Directory get location => cache.getArtifactDirectory(name);

  Future<bool> isUpToDate() async => location.existsSync();

  Future<void> update() async {
    final request = http.Request('GET', Uri.parse(storageUrl));
    final response = await cache.httpClient.send(request);

    await extractArtifact(response.stream, location.path);

    if (platform.isWindows) return;

    for (final executable in executables) {
      final result = await process.start(
        'chmod',
        ['+x', p.join(location.path, executable)],
      );
      await result.exitCode;
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
  Future<void> extractArtifact(
    http.ByteStream stream,
    String outputPath,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync();
    final artifactPath = p.join(tempDir.path, '$name.zip');
    await stream.pipe(File(artifactPath).openWrite());
    await cache.extractArchive(artifactPath, p.join(outputPath));
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
}

class BundleToolArtifact extends CachedArtifact {
  BundleToolArtifact({required super.cache, required super.platform});

  @override
  String get name => 'bundletool.jar';

  @override
  String get storageUrl {
    return 'https://github.com/google/bundletool/releases/download/1.14.1/bundletool-all-1.14.1.jar';
  }
}
