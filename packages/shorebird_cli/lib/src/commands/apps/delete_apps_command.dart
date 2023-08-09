import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template delete_app_command}
///
/// `shorebird apps delete`
/// Delete an existing app on Shorebird.
/// {@endtemplate}
class DeleteAppCommand extends ShorebirdCommand {
  /// {@macro delete_app_command}
  DeleteAppCommand() {
    argParser
      ..addOption(
        'app-id',
        help: '''
The unique application identifier.
Defaults to the app_id in "shorebird.yaml".''',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Release without confirmation if there are no errors.',
        negatable: false,
      );
  }

  @override
  String get description => 'Delete an existing app on Shorebird.';

  @override
  String get name => 'delete';

  @override
  Future<int>? run() async {
    final consoleLink = link(uri: Uri.parse('https://console.shorebird.dev'));
    logger.warn(
      '''
This command is deprecated and will be removed in a future release.
Please use $consoleLink instead.''',
    );

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final appIdArg = results['app-id'] as String?;
    final force = results['force'] == true;
    late final String appId;

    if (appIdArg == null) {
      String? defaultAppId;
      try {
        defaultAppId = shorebirdEnv.getShorebirdYaml()?.appId;
      } catch (_) {}

      appId = logger.prompt(
        '${lightGreen.wrap('?')} Enter the App ID',
        defaultValue: defaultAppId,
      );
    } else {
      appId = appIdArg;
    }

    final shouldProceed =
        force || logger.confirm('Deleting an app is permanent. Continue?');
    if (!shouldProceed) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    try {
      await codePushClientWrapper.codePushClient.deleteApp(appId: appId);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info(
      '${lightGreen.wrap('Deleted app: ${cyan.wrap(appId)}')}',
    );

    return ExitCode.success.code;
  }
}
