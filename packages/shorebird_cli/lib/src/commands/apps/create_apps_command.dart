import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template create_app_command}
///
/// `shorebird apps create`
/// Create a new app on Shorebird.
/// {@endtemplate}
class CreateAppCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro create_app_command}
  CreateAppCommand({
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
  String get description => 'Create a new app on Shorebird.';

  @override
  String get name => 'create';

  @override
  Future<int>? run() async {
    final session = auth.currentSession;
    if (session == null) {
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
      apiKey: session.apiKey,
      hostedUri: hostedUri,
    );

    try {
      await client.createApp(appId: appId);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info(
      '${lightGreen.wrap('Created new app: ${cyan.wrap(appId)}')}',
    );

    return ExitCode.success.code;
  }
}
