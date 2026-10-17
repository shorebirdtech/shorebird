import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template apps_unarchive_command}
/// `shorebird apps unarchive`
/// Resume serving patches for an archived app.
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
      'Unarchives an app.\n\n'
      'Devices are offered patches again, and new releases and patches can be '
      'created. Unarchiving an app that is not archived does nothing.\n\n'
      'Example output:\n'
      '  Unarchived app "<app-id>".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps unarchive --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final unarchiveError = await guardApiCall(
      () => codePushClientWrapper.unarchiveApp(appId: appId),
      code: JsonErrorCode.softwareError,
      message: 'Failed to unarchive app "$appId".',
    );
    if (unarchiveError != null) return unarchiveError;

    if (isJsonMode) {
      emitJsonSuccess({'app_id': appId, 'archived': false});
      return ExitCode.success.code;
    }

    logger.success('Unarchived app "$appId".');
    return ExitCode.success.code;
  }
}
