import 'package:args/command_runner.dart';
import 'package:cutler/config.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';
import 'package:mason_logger/mason_logger.dart';

/// Base class for Cutler subcommands.
abstract class CutlerCommand extends Command<int> {
  /// Constructs a new [CutlerCommand].
  CutlerCommand({
    required this.logger,
  });

  /// The logger to use for this command.
  final Logger logger;

  /// Update the repos if needed.
  void updateReposIfNeeded(Config config) {
    if (config.doUpdate) {
      final progress = logger.progress('Updating checkouts...');
      for (final repo in Repo.values) {
        progress.update('Updating ${repo.name}');
        repo.fetchAll();
      }
      progress.complete('Checkouts updated!');
    }
  }
}
