import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template channels_create_command}
/// `shorebird channels create`
/// Create a channel an app can publish to.
/// {@endtemplate}
class ChannelsCreateCommand extends ShorebirdCommand {
  /// {@macro channels_create_command}
  ChannelsCreateCommand() {
    argParser
      ..addOption(
        'name',
        help:
            'The name of the channel to create (e.g. "qa"), up to '
            '${CommonArguments.trackNameMaxLength} characters.',
        mandatory: true,
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
    if (channelName.isEmpty ||
        channelName.length > CommonArguments.trackNameMaxLength) {
      const message =
          'Channel name must be between 1 and '
          '${CommonArguments.trackNameMaxLength} characters.';
      if (isJsonMode) {
        emitJsonError(code: JsonErrorCode.usageError, message: message);
        return ExitCode.usage.code;
      }
      logger.err(message);
      return ExitCode.usage.code;
    }

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

    final existing = channels.firstWhereOrNull((c) => c.name == channelName);
    if (existing != null) {
      final message = 'Channel "$channelName" already exists.';
      if (isJsonMode) {
        emitJsonError(code: JsonErrorCode.usageError, message: message);
        return ExitCode.usage.code;
      }
      logger.err(message);
      return ExitCode.usage.code;
    }

    final Channel channel;
    try {
      channel = await codePushClientWrapper.createChannel(
        appId: appId,
        name: channelName,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message: 'Failed to create channel "$channelName".',
        );
        return e.exitCode;
      }
      rethrow;
    }

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
