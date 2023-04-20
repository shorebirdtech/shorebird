import 'dart:io';

import 'package:args/args.dart';

// https://github.com/dart-lang/sdk/issues/18466
// https://github.com/dart-lang/path/issues/117#issuecomment-1034313012
String expandUser(String path) {
  // This is not "well written", but eventually I guess we should
  // write one and publish it if Dart doesn't add an equivalent method.
  // If we're in CMD or PowerShell, we need to expand %USERPROFILE%. If we're
  // in WSL, we need to expand $HOME.
  // This should handle ~ and ~user.
  if (path.startsWith('~')) {
    final home = Platform.environment['HOME'];
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
  });
  final String checkoutsRoot;
  final bool verbose;
  final bool dryRun;
  final bool doUpdate;
}

late final Config config;

Config parseArgs(List<String> args) {
  final parser = ArgParser()
    ..addFlag('verbose', abbr: 'v')
    ..addOption(
      'root',
      defaultsTo: '.',
      help: 'Directory in which to find checkouts.',
    )
    ..addFlag('dry-run', defaultsTo: true, help: 'Do not actually run git.')
    ..addFlag('update', defaultsTo: true, help: 'Update checkouts.');
  final results = parser.parse(args);
  return Config(
    verbose: results['verbose'] as bool,
    checkoutsRoot: expandUser(results['root'] as String),
    dryRun: results['dry-run'] as bool,
    doUpdate: results['update'] as bool,
  );
}
