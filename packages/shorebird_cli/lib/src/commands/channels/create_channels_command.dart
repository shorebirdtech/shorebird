import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template create_channels_command}
/// `shorebird channels create`
/// Create a new channel for a Shorebird app.
/// {@endtemplate}
class CreateChannelsCommand extends ShorebirdCommand
    with AuthLoggerMixin, ShorebirdConfigMixin {
  /// {@macro create_channels_command}
  CreateChannelsCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser
      ..addOption(
        _appIdOption,
        help: 'The app id to create a channel for.',
      )
      ..addOption(
        _channelNameOption,
        help: 'The name of the channel to create.',
      );
  }

  static const String _appIdOption = 'app-id';
  static const String _channelNameOption = 'name';

  @override
  String get description => 'Create a new channel for a Shorebird app.';

  @override
  String get name => 'create';

  @override
  Future<int>? run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final appId =
        results[_appIdOption] as String? ?? getShorebirdYaml()?.appId.value;
    if (appId == null) {
      logger.err(
        '''
Could not find an app id.

You must either specify an app id via the "--$_appIdOption" flag or run this command from within a directory with a valid "shorebird.yaml" file.''',
      );
      return ExitCode.usage.code;
    }

    final channel = results[_channelNameOption] as String;

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new channel!'))}

📱 App ID: ${lightCyan.wrap(appId)}
📺 Channel: ${lightCyan.wrap(channel)}
''',
    );

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Creating channel');
    try {
      await client.createChannel(appId: appId, channel: channel);
      progress.complete();
    } catch (error) {
      progress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ New Channel Created!');

    return ExitCode.success.code;
  }
}
