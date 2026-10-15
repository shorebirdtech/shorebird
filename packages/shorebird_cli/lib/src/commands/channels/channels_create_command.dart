import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template channels_create_command}
/// `shorebird channels create`
/// Create a channel an app can publish to.
/// {@endtemplate}
class ChannelsCreateCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro channels_create_command}
  ChannelsCreateCommand() {
    argParser.addOption(
      'name',
      help:
          'The name of the channel to create (e.g. "qa"), up to '
          '${CommonArguments.trackNameMaxLength} characters.',
      mandatory: true,
    );
    addAppScopeOptions();
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Creates a channel an app can publish to.\n\n'
      'Channels are also created automatically when a patch is published '
      'with --track=<name>.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird channels create --app-id <id> --name qa --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final channelName = results['name'] as String;
    final nameError = CommonArguments.nameError(
      label: 'Channel name',
      value: channelName,
      maxLength: CommonArguments.trackNameMaxLength,
    );
    if (nameError != null) return reportError(message: nameError);

    late final List<Channel> channels;
    final fetchError = await guardApiCall(
      () async =>
          channels = await codePushClientWrapper.getChannels(appId: appId),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch channels for app "$appId".',
    );
    if (fetchError != null) return fetchError;

    final existing = channels.firstWhereOrNull((c) => c.name == channelName);
    if (existing != null) {
      final message = 'Channel "$channelName" already exists.';
      return reportError(message: message);
    }

    late final Channel channel;
    final createError = await guardApiCall(
      () async => channel = await codePushClientWrapper.createChannel(
        appId: appId,
        name: channelName,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to create channel "$channelName".',
    );
    if (createError != null) return createError;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'name': channelName,
        'channel': channel.toJson(),
      });
      return ExitCode.success.code;
    }

    logger.success('Created channel "$channelName".');
    return ExitCode.success.code;
  }
}
