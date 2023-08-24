import 'package:collection/collection.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';

/// Print VersionSet [versions] to stdout at a given [indent] level.
void printVersions(
  VersionSet versions, {
  int indent = 0,
  VersionSet? upstream,
}) {
  final repos = [
    Repo.flutter,
    Repo.engine,
    Repo.dart,
    Repo.buildroot,
  ];
  for (final repo in repos) {
    final string = "${' ' * indent}${repo.name.padRight(9)} ${versions[repo]}";
    // Include number of commits ahead of upstream.
    if (upstream != null) {
      final upstreamVersion = upstream[repo];
      final commitCount = repo.countCommits(
        from: upstreamVersion.ref,
        to: versions[repo].ref,
      );
      final commitsString = commitCount != 0 ? ' ($commitCount ahead)' : '';
      print('$string$commitsString');
    } else {
      print(string);
    }
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
  //  'dart_sdk_revision': 'ce926bc6dcf649bd31a396e4e3961196115727cd',
  // In our fork we use dart_sdk_revision, not dart_revision, since the former
  // points to our fork of the Dart SDK and the latter points to some base
  // revision for dart.googlesource.com/sdk.
  // For upstream we use 'dart_revision'.
  final dartLine = lines
          .firstWhereOrNull((line) => line.contains("'dart_sdk_revision': ")) ??
      lines.firstWhere((line) => line.contains("'dart_revision': "));
  final regexp = RegExp('([0-9a-f]{40})');
  final match = regexp.firstMatch(dartLine);
  if (match == null) {
    throw Exception('Failed to parse dart revision from $dartLine');
  }
  return match.group(0)!;
}
