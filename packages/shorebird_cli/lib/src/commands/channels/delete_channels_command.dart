import 'dart:async';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template delete_channels_command}
/// `shorebird channels delete`
/// Delete an existing channel for a Shorebird app.
/// {@endtemplate}
class DeleteChannelsCommand extends ShorebirdCommand
    with AuthLoggerMixin, ShorebirdConfigMixin {
  /// {@macro delete_channels_command}
  DeleteChannelsCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser
      ..addOption(
        _appIdOption,
        help: 'The app id that contains the channel to be deleted.',
      )
      ..addOption(
        _channelNameOption,
        help: 'The name of the channel to delete.',
      );
  }

  static const String _appIdOption = 'app-id';
  static const String _channelNameOption = 'name';

  @override
  String get description => 'Delete an existing channel for a Shorebird app.';

  @override
  String get name => 'delete';

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

    final appId = results[_appIdOption] as String? ?? getShorebirdYaml()?.appId;
    if (appId == null) {
      logger.err(
        '''
Could not find an app id.

You must either specify an app id via the "--$_appIdOption" flag or run this command from within a directory with a valid "shorebird.yaml" file.''',
      );
      return ExitCode.usage.code;
    }

    final channelName = results[_channelNameOption] as String? ??
        logger.prompt(
          '''${lightGreen.wrap('?')} What is the name of the channel you would like to delete?''',
        );
    ;

    final getChannelsProgress = logger.progress('Fetching channels');
    final List<Channel> channels;
    try {
      channels = await client.getChannels(appId: appId);
      getChannelsProgress.complete();
    } catch (error) {
      getChannelsProgress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    final channel = channels.firstWhereOrNull((c) => c.name == channelName);
    if (channel == null) {
      logger.err(
        '''
Could not find a channel with the name "$channelName".

Available channels:
${channels.map((c) => '  - ${c.name}').join('\n')}''',
      );
      return ExitCode.software.code;
    }

    logger.info(
      '''

${styleBold.wrap(lightGreen.wrap('🗑️  Ready to delete an existing channel!'))}

📱 App ID: ${lightCyan.wrap(appId)}
📺 Channel: ${lightCyan.wrap(channel.name)}
''',
    );

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Deleting channel');
    try {
      await client.deleteChannel(channelId: channel.id);
      progress.complete();
    } catch (error) {
      progress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ Channel Deleted!');

    return ExitCode.success.code;
  }
}
