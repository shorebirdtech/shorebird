import 'dart:io';

import 'package:args/args.dart';

// https://github.com/dart-lang/sdk/issues/18466
// https://github.com/dart-lang/path/issues/117#issuecomment-1034313012
String expandUser(String path) {
  // This is not "well written", but eventually I guess we should
  // write one and publish it if Dart doesn't.
  // If we're in CMD or PowerShell, we need to expand %USERPROFILE%. If we're
  // in WSL, we need to expand $HOME.
  // This should handle ~ and ~user.
  if (path.startsWith('~')) {
    final home = Platform.environment['HOME'];
    if (home == null) {
      throw Exception("Failed to expand $path");
    }
    return path.replaceFirst('~', home);
  }
  return path;
}

// Config is basically just our typed ArgResults held as a global.
class Config {
  final String checkoutsRoot;
  final bool verbose;
  final bool dryRun;
  final bool doUpdate;

  Config({
    required this.checkoutsRoot,
    required this.verbose,
    required this.dryRun,
    required this.doUpdate,
  });
}

late final Config config;

Config parseArgs(List<String> args) {
  final parser = ArgParser();
  parser.addFlag('verbose', abbr: 'v', defaultsTo: false);
  parser.addOption('root',
      defaultsTo: '.', help: 'Directory in which to find checkouts.');
  parser.addFlag('dry-run', defaultsTo: true, help: 'Do not actually run git.');
  parser.addFlag('update', defaultsTo: true, help: 'Update checkouts.');
  final results = parser.parse(args);
  return Config(
    verbose: results['verbose'] as bool,
    checkoutsRoot: expandUser(results['root'] as String),
    dryRun: results['dry-run'] as bool,
    doUpdate: results['update'] as bool,
  );
}
