import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template create_app_command}
///
/// `shorebird apps create`
/// Create a new app on Shorebird.
/// {@endtemplate}
class CreateAppCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdCreateAppMixin {
  /// {@macro create_app_command}
  CreateAppCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser.addOption(
      'app-name',
      help: '''
The display name of your application.
Defaults to the name in "pubspec.yaml".''',
    );
  }

  @override
  String get description => 'Create a new app on Shorebird.';

  @override
  String get name => 'create';

  @override
  Future<int>? run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final appName = results['app-name'] as String?;
    late final App app;
    try {
      app = await createApp(appName: appName);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info(
      '''${lightGreen.wrap('Created ${cyan.wrap(app.displayName)} ${styleDim.wrap(cyan.wrap('(${app.id})'))}')}''',
    );

    return ExitCode.success.code;
  }
}
