import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template create_collaborators_command}
/// `shorebird collaborators create`
/// Create a new collaborator for a Shorebird app.
/// {@endtemplate}
class CreateCollaboratorsCommand extends ShorebirdCommand
    with AuthLoggerMixin, ShorebirdConfigMixin, ShorebirdCreateAppMixin {
  /// {@macro create_collaborators_command}
  CreateCollaboratorsCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser
      ..addOption(
        'app-id',
        help: '''
The app ID to create a collaborator for.
Defaults to the app_id in the shorebird.yaml.''',
      )
      ..addOption('member', help: '''
The user id
''');
  }

  @override
  String get description => 'Create a new collaborator for a Shorebird app.';

  @override
  String get name => 'create';

  @override
  Future<int>? run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
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
