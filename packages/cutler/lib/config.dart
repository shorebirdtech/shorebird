import 'dart:io';

// https://github.com/dart-lang/sdk/issues/18466
// https://github.com/dart-lang/path/issues/117#issuecomment-1034313012
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
class Config {
  Config({
    required this.checkoutsRoot,
    required this.verbose,
    required this.dryRun,
    required this.doUpdate,
    required this.flutterChannel,
  });
  final String checkoutsRoot;
  final bool verbose;
  final bool dryRun;
  final bool doUpdate;
  final String flutterChannel;

  final String shorebirdReleaseBranch = 'origin/stable';
}

late final Config config;
