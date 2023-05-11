import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';

void printVersions(VersionSet versions, int indent) {
  print("${' ' * indent}flutter   ${versions.flutter}");
  print("${' ' * indent}engine    ${versions.engine}");
  print("${' ' * indent}buildroot ${versions.buildroot}");
}

VersionSet getFlutterVersions(String flutterHash) {
  final engineHash = Repo.flutter
      .contentsAtPath(flutterHash, 'bin/internal/engine.version')
      .trim();
  final depsContents =
      Repo.engine.contentsAtPath(engineHash, Paths.engineDEPS.path);
  final buildrootVersion = parseBuildRoot(depsContents);
  return VersionSet(
    engine: Repo.engine.versionFrom(engineHash),
    flutter: Repo.flutter.versionFrom(flutterHash),
    buildroot: Repo.buildroot.versionFrom(buildrootVersion),
  );
}

String parseBuildRoot(String depsContents) {
  final lines = depsContents.split('\n');
  // Example:
  //   'src': 'https://github.com/flutter/buildroot.git' + '@' + '059d155b4d452efd9c4427c45cddfd9445144869',
  final buildrootLine = lines.firstWhere((line) => line.contains("'src': "));
  final regexp = RegExp('([0-9a-f]{40})');
  final match = regexp.firstMatch(buildrootLine);
  if (match == null) {
    throw Exception('Failed to parse buildroot version from $buildrootLine');
  }
  return match.group(0)!;
}
