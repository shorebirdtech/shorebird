import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// {@template sample_command}
///
/// `shorebird sample`
/// A [Command] to exemplify a sub command
/// {@endtemplate}
class PublishCommand extends Command<int> {
  /// {@macro sample_command}
  PublishCommand({required Logger logger}) : _logger = logger;

  @override
  String get description => 'Publish an update.';

  @override
  String get name => 'publish';

  final Logger _logger;

  @override
  Future<int> run() async {
    _logger.info('Coming soon...');
    return ExitCode.success.code;
  }
}
