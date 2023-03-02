import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:version/version.dart';

int _compareVersions(String a, String b) {
  return Version.parse(a).compareTo(Version.parse(b));
}

class VersionStore {
  const VersionStore._({required this.cachePath});

  static void init({required String cachePath}) {
    _instance ??= VersionStore._(cachePath: cachePath);
  }

  final String cachePath;

  static VersionStore? _instance;

  // ignore: prefer_constructors_over_static_methods
  static VersionStore get instance {
    return _instance ??= const VersionStore._(cachePath: 'cache');
  }

  // Should take an api key/product name, etc.
  String getNextVersion() {
    final latest = latestVersionForClient('client') ?? '0.0.0';
    final next = Version.parse(latest).incrementPatch().toString();
    return next;
  }

  void addVersion(String version, List<int> bytes) {
    Directory(cachePath).createSync(recursive: true);
    final path = filePathForVersion(version);
    File(path).writeAsBytesSync(bytes);
  }

  Iterable<String> versionsForClientId(String clientId) {
    // This should use the clientId to get a productId and look up the versions
    // based on productId/architecture, etc.
    try {
      final dir = Directory(cachePath);
      final files = dir.listSync();
      return files.map((e) => p.basenameWithoutExtension(e.path));
    } catch (e) {
      return [];
    }
  }

  String? latestVersionForClient(String clientId, {String? currentVersion}) {
    final versions = versionsForClientId(clientId).toList()
      ..sort(_compareVersions);
    if (versions.isEmpty) return null;
    if (versions.last == currentVersion) return null;

    return versions.last;
  }

  String filePathForVersion(String version) => '$cachePath/$version.txt';
}
