import 'dart:io';

import 'package:path/path.dart' as p;

// https://github.com/dart-lang/sdk/issues/18466
// https://github.com/dart-lang/path/issues/117#issuecomment-1034313012
/// Expands a path that may contain a user directory (`~`). If [env] is
/// provided, it will be used instead of [Platform.environment].
String expandUser(String path, {Map<String, String>? env}) {
  // This is not "well written", but eventually I guess we should
  // write one and publish it if Dart doesn't add an equivalent method.
  // If we're in CMD or PowerShell, we need to expand %USERPROFILE%. If we're
  // in WSL, we need to expand $HOME.
  // This should handle ~ and ~user.
  final environment = env ?? Platform.environment;
  if (path.startsWith('~')) {
    final home = environment['HOME'];
    if (home == null) {
      throw Exception('Failed to expand $path');
    }
    return path.replaceFirst('~', home);
  }
  return path;
}

// This behavior belongs in the Dart SDK somewhere.
/// Find the package root for the current running script.
String findPackageRoot({String? scriptPath}) {
  final path = scriptPath ?? Platform.script.path;
  // e.g. `dart run bin/cutler.dart`
  if (path.endsWith('.dart')) {
    final binPath = p.dirname(path);
    return p.dirname(binPath);
  }
  // `dart run` pre-compiles into a snapshot and then runs, e.g.
  // .../packages/cutler/.dart_tool/pub/bin/cutler/cutler.dart-3.0.2.snapshot
  if (path.endsWith('.snapshot') && path.contains('.dart_tool')) {
    return path.split('.dart_tool').first;
  }
  throw UnimplementedError('Could not find package root: $path');
}

// Config is basically just our typed ArgResults held as a global.
/// Global configuration object for Cutler.
class Config {
  /// Constructs a new [Config].
  Config({
    required this.checkoutsRoot,
    required this.dryRun,
    required this.doUpdate,
    required this.flutterChannel,
  });

  /// The root directory where checkouts can be found.
  final String checkoutsRoot;

  /// Whether to perform a dry run.
  final bool dryRun;

  /// Whether to update checkouts.
  final bool doUpdate;

  /// The Flutter channel to use.
  final String flutterChannel;

  /// The name of the release branch for Shorebird.
  final String shorebirdReleaseBranch = 'origin/stable';
}
