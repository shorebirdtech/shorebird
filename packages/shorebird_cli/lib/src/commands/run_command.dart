import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template run_command}
/// `shorebird run`
/// Run the Flutter application.
/// {@endtemplate}
class RunCommand extends ShorebirdCommand
    with AuthLoggerMixin, ShorebirdValidationMixin, ShorebirdConfigMixin {
  /// {@macro run_command}
  RunCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.validators,
  });

  @override
  String get description => 'Run the Flutter application.';

  @override
  String get name => 'run';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    logger.info('Running app...');
    final flutter = await process.start(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        ...results.rest
      ],
      runInShell: true,
    );

    flutter.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    flutter.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    return flutter.exitCode;
  }
}
