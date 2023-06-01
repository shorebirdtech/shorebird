import 'dart:io';

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

// Config is basically just our typed ArgResults held as a global.
/// Global configuration object for Cutler.
class Config {
  /// Constructs a new [Config].
  Config({
    required this.checkoutsRoot,
    required this.verbose,
    required this.dryRun,
    required this.doUpdate,
    required this.flutterChannel,
  });

  /// The root directory where checkouts can be found.
  final String checkoutsRoot;

  /// Whether to print verbose output.
  final bool verbose;

  /// Whether to perform a dry run.
  final bool dryRun;

  /// Whether to update checkouts.
  final bool doUpdate;

  /// The Flutter channel to use.
  final String flutterChannel;

  /// The name of the release branch for Shorebird.
  final String shorebirdReleaseBranch = 'origin/stable';
}

/// The global configuration object for Cutler.
late final Config config;
