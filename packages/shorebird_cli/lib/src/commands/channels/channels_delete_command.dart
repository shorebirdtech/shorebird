import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_name_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The channels backing Shorebird's built-in deployment tracks.
///
/// Deleting one stops patch delivery for every device on that track, so the
/// CLI calls it out ahead of the confirmation gate.
final _defaultTrackNames = <String>{
  DeploymentTrack.stable.value,
  DeploymentTrack.beta.value,
  DeploymentTrack.staging.value,
};

/// {@template channels_delete_command}
/// `shorebird channels delete`
/// Delete a channel from an app.
/// {@endtemplate}
class ChannelsDeleteCommand extends ShorebirdCommand with ConfirmNameArgument {
  /// {@macro channels_delete_command}
  ChannelsDeleteCommand() {
    argParser
      ..addOption(
        'name',
        help: 'The name of the channel to delete (e.g. "qa").',
        mandatory: true,
      )
      ..addOption(
        confirmNameArgName,
        help:
            'The name of the channel again. Must match exactly, which is how '
            'the delete is confirmed.',
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to use (e.g. "prod").',
      );
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Deletes a channel from an app.\n\n'
      'Devices on the channel stop receiving patches. Deleting stable, beta, '
      'or staging affects every device on that track.\n\n'
      'Requires --$confirmNameArgName=<channel name>; there is no prompt, so '
      'this behaves the same in a terminal and in CI.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird channels delete --app-id <id> --name qa '
        '--confirm-name qa --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final channelName = results['name'] as String;

    final List<Channel> channels;
    try {
      channels = await codePushClientWrapper.getChannels(appId: appId);
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch channels for app "$appId".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    final channel = channels.firstWhereOrNull((c) => c.name == channelName);
    if (channel == null) {
      final message = 'No channel named "$channelName" for app "$appId".';
      final available = channels.map((c) => c.name).join(', ');
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: message,
          hint: 'Available channels: $available',
        );
        return ExitCode.usage.code;
      }
      logger
        ..err(message)
        ..info('Available channels: $available');
      return ExitCode.usage.code;
    }

    final isDefaultTrack = _defaultTrackNames.contains(channelName);
    // Warn ahead of the confirmation gate so a caller who has not yet passed
    // --confirm-name sees the stakes before echoing the name back.
    if (isDefaultTrack && !isJsonMode) {
      logger.warn(
        '"$channelName" is one of Shorebird\'s built-in tracks. Deleting it '
        'affects every device on that track.',
      );
    }

    final gateErrorCode = checkConfirmName(
      expected: channelName,
      resourceDescription: 'channel "$channelName"',
    );
    if (gateErrorCode != null) return gateErrorCode;

    try {
      await codePushClientWrapper.deleteChannel(
        appId: appId,
        channelId: channel.id,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message: 'Failed to delete channel "$channelName".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'name': channelName,
        'channel_id': channel.id,
        'is_default_track': isDefaultTrack,
        'deleted': true,
      });
      return ExitCode.success.code;
    }

    logger.success('Deleted channel "$channelName".');
    return ExitCode.success.code;
  }
}
