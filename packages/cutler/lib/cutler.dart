import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cutler/commands/commands.dart';
import 'package:cutler/config.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// The main Cutler command runner.
class Cutler extends CommandRunner<int> {
  /// Constructs a new [Cutler] command runner.
  Cutler() : super('cutler', 'A tool for maintaining forks of Flutter.') {
    addCommand(VersionsCommand());

    argParser
      ..addFlag('verbose', abbr: 'v')
      ..addOption(
        'root',
        help: 'Directory in which to find checkouts.',
      )
      ..addOption(
        'flutter-channel',
        defaultsTo: 'stable',
        help: 'Upstream channel to propose rebasing onto.',
      )
      ..addFlag('dry-run', defaultsTo: true, help: 'Do not actually run git.')
      ..addFlag('update', defaultsTo: true, help: 'Update checkouts.');
  }

  /// Global config set during arg parsing.
  late Config config;

  /// Lists directories missing from the proposed root directory.
  Iterable<String> missingDirectories(String rootDir) {
    return Repo.values.map((repo) => '$rootDir/${repo.path}').where(
          (path) => !Directory(path).existsSync(),
        );
  }

  /// Find a valid root directory for checkouts.
  String fallbackRootDir() {
    final cutlerRoot = findPackageRoot();
    final packagesDir = p.dirname(cutlerRoot);
    final shorebirdDir = p.dirname(packagesDir);
    final fallbackDirectories = <String>[
      Directory.current.path,
      p.dirname(shorebirdDir),
      // Internal checkouts use a _shorebird wrapper directory.
      p.dirname(p.dirname(shorebirdDir)),
    ];
    for (final directory in fallbackDirectories) {
      if (missingDirectories(directory).isEmpty) {
        logger.info('Using $directory as checkouts root.');
        return directory;
      }
    }
    logger.err('Failed to find a valid checkouts root, tried:\n'
        '${fallbackDirectories.join('\n')}');
    return ''; // Returning an invalid directory will cause validation to fail.
  }

  @override
  ArgResults parse(Iterable<String> args) {
    final results = super.parse(args);

    final rootDir = results['root'] as String? ?? fallbackRootDir();

    final missingDirs = missingDirectories(rootDir);
    if (missingDirs.isNotEmpty) {
      logger
        ..err('Could not find a valid checkouts root.')
        ..err('--root must be a directory containing the '
            'following:\n${Repo.values.map((r) => r.path).join('\n')}')
        ..err('Missing directories:\n${missingDirs.join('\n')}');
      exit(1);
    }

    config = Config(
      checkoutsRoot: expandUser(rootDir),
      dryRun: results['dry-run'] as bool,
      doUpdate: results['update'] as bool,
      flutterChannel: results['flutter-channel'] as String,
    );

    if (results['verbose'] as bool) {
      logger.level = Level.verbose;
    }

    return results;
  }
}
