import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Base class for Cutler subcommands.
abstract class CutlerCommand extends Command<int> {
  /// Constructs a new [CutlerCommand].
  CutlerCommand({
    required this.logger,
  });

  /// The logger to use for this command.
  final Logger logger;
}
