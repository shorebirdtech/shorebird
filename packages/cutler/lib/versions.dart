import 'package:collection/collection.dart';
import 'package:cutler/checkout.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';

/// Print VersionSet [versions] to stdout at a given [indent] level.
void printVersions(
  Checkouts checkouts,
  VersionSet versions, {
  int indent = 0,
  VersionSet? upstream,
  bool trailingNewline = true,
}) {
  final repos = [
    Repo.flutter,
    Repo.engine,
    Repo.dart,
    Repo.buildroot,
  ];
  for (final repo in repos) {
    final checkout = checkouts[repo];
    final string = "${' ' * indent}${repo.name.padRight(9)} ${versions[repo]}";
    // Include number of commits ahead of upstream.
    if (upstream != null) {
      final upstreamVersion = upstream[repo];
      final commitCount = checkout.countCommits(
        from: upstreamVersion.ref,
        to: versions[repo].ref,
      );
      final commitsString = commitCount != 0 ? ' ($commitCount ahead)' : '';
      logger.info('$string$commitsString');
    } else {
      logger.info(string);
    }
  }
  if (trailingNewline) {
    logger.info('');
  }
}

/// Returns a [VersionSet] for Flutter for a given [flutterHash].
/// e.g. `flutterHash` might be `origin/stable` or `v1.22.0-12.1.pre`.
/// and this would return the set of versions (engine and buildroot) that
/// Flutter depends on for that release.
VersionSet getFlutterVersions(Checkouts checkouts, String flutterHash) {
  final flutter = checkouts.flutter;
  final engine = checkouts.engine;
  final buildroot = checkouts.buildroot;
  final dart = checkouts.dart;
  final engineHash =
      flutter.contentsAtPath(flutterHash, 'bin/internal/engine.version').trim();
  final depsContents = engine.contentsAtPath(engineHash, Paths.engineDEPS.path);
  final buildrootHash = parseBuildrootRevision(depsContents);
  final dartHash = parseDartRevision(depsContents);
  return VersionSet(
    engine: engine.versionFrom(engineHash),
    flutter: flutter.versionFrom(flutterHash),
    buildroot: buildroot.versionFrom(buildrootHash),
    dart: dart.versionFrom(dartHash),
  );
}

/// Parses the given DEPS file contents and returns the buildroot revision.
String parseBuildrootRevision(String depsContents) {
  final lines = depsContents.split('\n');
  // Example:
  //   'src': 'https://github.com/flutter/buildroot.git' + '@' + '059d155b4d452efd9c4427c45cddfd9445144869',
  final buildrootLine =
      lines.firstWhereOrNull((line) => line.contains("'src': "));
  if (buildrootLine == null) {
    throw Exception('Failed to find buildroot revision in DEPS file');
  }
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
