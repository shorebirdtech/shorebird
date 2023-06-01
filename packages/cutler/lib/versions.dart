import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';

/// Print VersionSet [versions] to stdout at a given [indent] level.
void printVersions(VersionSet versions, {int indent = 0}) {
  final repos = [
    Repo.flutter,
    Repo.engine,
    Repo.dart,
    Repo.buildroot,
  ];
  for (final repo in repos) {
    print("${' ' * indent}${repo.name.padRight(9)} ${versions[repo]}");
  }
}

/// Returns a [VersionSet] for Flutter for a given [flutterHash].
/// e.g. `flutterHash` might be `origin/stable` or `v1.22.0-12.1.pre`.
/// and this would return the set of versions (engine and buildroot) that
/// Flutter depends on for that release.
VersionSet getFlutterVersions(String flutterHash) {
  final engineHash = Repo.flutter
      .contentsAtPath(flutterHash, 'bin/internal/engine.version')
      .trim();
  final depsContents =
      Repo.engine.contentsAtPath(engineHash, Paths.engineDEPS.path);
  final buildrootHash = parseBuildrootRevision(depsContents);
  final dartHash = parseDartRevision(depsContents);
  return VersionSet(
    engine: Repo.engine.versionFrom(engineHash),
    flutter: Repo.flutter.versionFrom(flutterHash),
    buildroot: Repo.buildroot.versionFrom(buildrootHash),
    dart: Repo.dart.versionFrom(dartHash),
  );
}

/// Parses the given DEPS file contents and returns the buildroot revision.
String parseBuildrootRevision(String depsContents) {
  final lines = depsContents.split('\n');
  // Example:
  //   'src': 'https://github.com/flutter/buildroot.git' + '@' + '059d155b4d452efd9c4427c45cddfd9445144869',
  final buildrootLine = lines.firstWhere((line) => line.contains("'src': "));
  final regexp = RegExp('([0-9a-f]{40})');
  final match = regexp.firstMatch(buildrootLine);
  if (match == null) {
    throw Exception('Failed to parse buildroot revision from $buildrootLine');
  }
  return match.group(0)!;
}

/// Parses the given DEPS file contents and returns the dart-lang/sdk revision.
String parseDartRevision(String depsContents) {
  final lines = depsContents.split('\n');
  // Example:
  //  'dart_revision': 'ce926bc6dcf649bd31a396e4e3961196115727cd',
  final dartLine =
      lines.firstWhere((line) => line.contains("'dart_revision': "));
  final regexp = RegExp('([0-9a-f]{40})');
  final match = regexp.firstMatch(dartLine);
  if (match == null) {
    throw Exception('Failed to parse dart revision from $dartLine');
  }
  return match.group(0)!;
}
