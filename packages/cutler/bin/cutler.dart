import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cutler/commands/commands.dart';
import 'package:cutler/config.dart';
import 'package:cutler/model.dart';

class Cutler extends CommandRunner<int> {
  Cutler() : super('cutler', 'A tool for maintaining forks of Flutter.') {
    addCommand(RebaseCommand());
    addCommand(PrintVersionsCommand());

    argParser
      ..addFlag('verbose', abbr: 'v')
      ..addOption(
        'root',
        defaultsTo: '.',
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

  @override
  ArgResults parse(Iterable<String> args) {
    final results = super.parse(args);
    config = Config(
      checkoutsRoot: expandUser(results['root'] as String),
      verbose: results['verbose'] as bool,
      dryRun: results['dry-run'] as bool,
      doUpdate: results['update'] as bool,
      flutterChannel: results['flutter-channel'] as String,
    );
    for (final repo in Repo.values) {
      final path = '${config.checkoutsRoot}/${repo.path}';
      if (!Directory(path).existsSync()) {
        throw Exception(
          'Directory $path does not exist, are you sure --root is correct?',
        );
      }
    }
    return results;
  }
}

void main(List<String> args) {
  Cutler().run(args);
}
