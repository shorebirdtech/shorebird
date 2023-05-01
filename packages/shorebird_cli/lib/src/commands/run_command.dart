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
  }) {
    argParser
      ..addOption(
        'device-id',
        abbr: 'd',
        help: 'Target device id or name.',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      );
  }

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

    final deviceId = results['device-id'] as String?;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final flutter = await process.start(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        if (deviceId != null) '--device-id=$deviceId',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
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
