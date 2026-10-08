import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template channels_list_command}
/// `shorebird channels list`
/// List the channels an app can publish to.
/// {@endtemplate}
class ChannelsListCommand extends ShorebirdCommand {
  /// {@macro channels_list_command}
  ChannelsListCommand() {
    argParser
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
  String get name => 'list';

  @override
  String get description =>
      'Lists the channels an app can publish to.\n\n'
      'Example output (space-separated: id  name):\n'
      '  1  stable\n'
      '  2  beta\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird channels list --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

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

    if (isJsonMode) {
      emitJsonSuccess({
        'channels': [for (final channel in channels) channel.toJson()],
      });
      return ExitCode.success.code;
    }

    if (channels.isEmpty) {
      logger.info('No channels found for app $appId.');
      return ExitCode.success.code;
    }

    for (final channel in channels) {
      logger.info('${channel.id}  ${channel.name}');
    }
    return ExitCode.success.code;
  }
}
