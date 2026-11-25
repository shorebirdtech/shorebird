import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_unarchive_command}
/// `shorebird apps unarchive`
/// Bring an archived app back to serving patches.
/// {@endtemplate}
class AppsUnarchiveCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro apps_unarchive_command}
  AppsUnarchiveCommand() {
    addAppScopeOptions();
  }

  @override
  String get name => 'unarchive';

  @override
  String get description =>
      'Brings an archived app back to serving patches.\n\n'
      'The app counts against your app quota again, and takes new releases '
      'and patches.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps unarchive --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    late final AppMetadata app;
    final fetchError = await guardApiCall(
      () async => app = await codePushClientWrapper.getApp(appId: appId),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch app "$appId".',
    );
    if (fetchError != null) return fetchError;

    final unarchiveError = await guardApiCall(
      () => codePushClientWrapper.unarchiveApp(appId: appId),
      code: JsonErrorCode.softwareError,
      message: 'Failed to unarchive app "$appId".',
    );
    if (unarchiveError != null) return unarchiveError;

    if (isJsonMode) {
      emitJsonSuccess({'app_id': appId, 'display_name': app.displayName});
      return ExitCode.success.code;
    }

    logger.success('Unarchived "${app.displayName}".');
    return ExitCode.success.code;
  }
}
