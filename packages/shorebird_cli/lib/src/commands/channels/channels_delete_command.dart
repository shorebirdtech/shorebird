import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/confirm_name_argument.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The channels backing Shorebird's built-in deployment tracks.
///
/// These are permanent: the server refuses to delete them (deleting one would
/// unpublish every patch on that track), so the CLI refuses up front instead
/// of sending a request that can only fail.
final _defaultTrackNames = <String>{
  DeploymentTrack.stable.value,
  DeploymentTrack.beta.value,
  DeploymentTrack.staging.value,
};

/// {@template channels_delete_command}
/// `shorebird channels delete`
/// Delete a channel from an app.
/// {@endtemplate}
class ChannelsDeleteCommand extends ShorebirdCommand
    with AppScopedCommand, ConfirmNameArgument {
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
      );
    addAppScopeOptions();
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Deletes a channel from an app.\n\n'
      'Devices on the channel stop receiving patches.\n\n'
      'The built-in tracks stable, beta, and staging are permanent and cannot '
      'be deleted.\n\n'
      'Requires --$confirmNameArgName=<channel name>; there is no prompt, so '
      'this behaves the same in a terminal and in CI. Run '
      '"shorebird channels list" to see the names an app has.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird channels delete --app-id <id> --name qa '
        '--confirm-name qa --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final channelName = results['name'] as String;

    if (_defaultTrackNames.contains(channelName)) {
      return reportError(
        message:
            '"$channelName" is one of Shorebird\'s built-in tracks and cannot '
            'be deleted.',
        hint:
            'Deleting it would unpublish every patch on that track. Only '
            'channels you created can be deleted.',
      );
    }

    late final List<Channel> channels;
    final fetchError = await guardApiCall(
      () async =>
          channels = await codePushClientWrapper.getChannels(appId: appId),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch channels for app "$appId".',
    );
    if (fetchError != null) return fetchError;

    final channel = channels.firstWhereOrNull((c) => c.name == channelName);
    if (channel == null) {
      final message = 'No channel named "$channelName" for app "$appId".';
      final available = channels.map((c) => c.name).join(', ');
      return reportError(
        message: message,
        hint: 'Available channels: $available',
      );
    }

    final gateErrorCode = checkConfirmName(
      expected: channelName,
      resourceDescription: 'channel "$channelName"',
    );
    if (gateErrorCode != null) return gateErrorCode;

    final deleteError = await guardApiCall(
      () => codePushClientWrapper.deleteChannel(
        appId: appId,
        channelId: channel.id,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to delete channel "$channelName".',
    );
    if (deleteError != null) return deleteError;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'name': channelName,
        'channel_id': channel.id,
        'deleted': true,
      });
      return ExitCode.success.code;
    }

    logger.success('Deleted channel "$channelName".');
    return ExitCode.success.code;
  }
}
