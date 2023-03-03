import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:version/version.dart';

int _compareVersions(String a, String b) {
  return Version.parse(a).compareTo(Version.parse(b));
}

class VersionStore {
  const VersionStore({required this.cachePath});

  final String cachePath;

  Directory get cacheDir {
    return Directory(p.join(Directory.current.path, cachePath));
  }

  // Should take an api key/product name, etc.
  String getNextVersion() {
    final latest = latestVersionForClient('client') ?? '0.0.0';
    final next = Version.parse(latest).incrementPatch().toString();
    return next;
  }

  void addVersion(String version, List<int> bytes) {
    cacheDir.createSync(recursive: true);
    final path = filePathForVersion(version);
    File(path).writeAsBytesSync(bytes);
  }

  String? latestVersionForClient(String clientId, {String? currentVersion}) {
    final versions = _versionsForClientId(clientId).toList()
      ..sort(_compareVersions);
    if (versions.isEmpty) return null;
    if (versions.last == currentVersion) return null;

    return versions.last;
  }

  String filePathForVersion(String version) {
    return p.join(cacheDir.path, '$version.txt');
  }

  Iterable<String> _versionsForClientId(String clientId) {
    // This should use the clientId to get a productId and look up the versions
    // based on productId/architecture, etc.
    try {
      final dir = cacheDir;
      final files = dir.listSync();
      return files.map((e) => p.basenameWithoutExtension(e.path));
    } catch (e) {
      return [];
    }
  }
}
