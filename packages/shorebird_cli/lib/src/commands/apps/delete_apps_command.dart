import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template delete_app_command}
///
/// `shorebird apps delete`
/// Delete an existing app on Shorebird.
/// {@endtemplate}
class DeleteAppCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro delete_app_command}
  DeleteAppCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser.addOption(
      'app-id',
      help: '''
The unique application identifier.
Defaults to the app_id in "shorebird.yaml".''',
    );
  }

  @override
  String get description => 'Delete an existing app on Shorebird.';

  @override
  String get name => 'delete';

  @override
  Future<int>? run() async {
    if (!auth.isAuthenticated) {
      logger.err('You must be logged in.');
      return ExitCode.noUser.code;
    }

    final appIdArg = results['app-id'] as String?;
    late final String appId;

    if (appIdArg == null) {
      String? defaultAppId;
      try {
        defaultAppId = getShorebirdYaml()?.appId;
      } catch (_) {}

      appId = logger.prompt(
        '${lightGreen.wrap('?')} Enter the App ID',
        defaultValue: defaultAppId,
      );
    } else {
      appId = appIdArg;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final confirm = logger.confirm('Deleting an app is permanent. Continue?');
    if (!confirm) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    try {
      await client.deleteApp(appId: appId);
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
