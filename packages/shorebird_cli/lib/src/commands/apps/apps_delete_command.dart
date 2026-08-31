import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_name_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_delete_command}
/// `shorebird apps delete`
/// Permanently delete an app and every artifact belonging to it.
/// {@endtemplate}
class AppsDeleteCommand extends ShorebirdCommand with ConfirmNameArgument {
  /// {@macro apps_delete_command}
  AppsDeleteCommand() {
    argParser
      ..addOption(
        confirmNameArgName,
        help:
            "The app's current display name. Must match exactly, which is how "
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
      'Permanently deletes an app.\n\n'
      'Every release and patch artifact belonging to the app is deleted from '
      'storage. This cannot be undone.\n\n'
      'Requires --$confirmNameArgName=<current display name>; there is no '
      'prompt, so this behaves the same in a terminal and in CI. Run '
      '"shorebird apps list" to get the exact name.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps delete --app-id <id> --confirm-name "Acme Mobile" '
        '--json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final AppMetadata app;
    final List<Release> releases;
    try {
      app = await codePushClientWrapper.getApp(appId: appId);
      releases = await codePushClientWrapper.getReleases(appId: appId);
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch app "$appId".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    final platforms = <String>{
      for (final release in releases)
        ...release.platformStatuses.keys.map((platform) => platform.name),
    }.toList()..sort();

    final gateErrorCode = checkConfirmName(
      expected: app.displayName,
      resourceDescription: 'app "${app.displayName}" ($appId)',
    );
    if (gateErrorCode != null) return gateErrorCode;

    try {
      await codePushClientWrapper.deleteApp(appId: appId);
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message: 'Failed to delete app "$appId".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'display_name': app.displayName,
        'release_count': releases.length,
        'platforms': platforms,
        'deleted': true,
      });
      return ExitCode.success.code;
    }

    logger.success('Deleted "${app.displayName}" ($appId).');
    return ExitCode.success.code;
  }
}
