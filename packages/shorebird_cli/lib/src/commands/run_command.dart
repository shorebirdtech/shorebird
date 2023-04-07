import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template run_command}
/// `shorebird run`
/// Run the Flutter application.
/// {@endtemplate}
class RunCommand extends ShorebirdCommand
    with ShorebirdValidationMixin, ShorebirdConfigMixin {
  /// {@macro run_command}
  RunCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.startProcess,
    super.validators,
  });

  @override
  String get description => 'Run the Flutter application.';

  @override
  String get name => 'run';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger
        ..err('You must be logged in to run.')
        ..err("Run 'shorebird login' to log in and try again.");
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    logger.info('Running app...');
    final process = await startProcess(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        ...results.rest
      ],
      runInShell: true,
    );

    process.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    process.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    return process.exitCode;
  }
}
