import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template apps_archive_command}
/// `shorebird apps archive`
/// Stop serving patches for an app and refuse new releases and patches.
/// {@endtemplate}
class AppsArchiveCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro apps_archive_command}
  AppsArchiveCommand() {
    addAppScopeOptions();
  }

  @override
  String get name => 'archive';

  @override
  String get description =>
      'Archives an app.\n\n'
      'Devices keep the patch they already have but are offered no new ones, '
      'and new releases and patches are refused until the app is unarchived. '
      'Releases, patches and collaborators are kept. Undo with '
      '`shorebird apps unarchive`.\n\n'
      'Example output:\n'
      '  Archived app "<app-id>".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps archive --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final archiveError = await guardApiCall(
      () => codePushClientWrapper.archiveApp(appId: appId),
      code: JsonErrorCode.softwareError,
      message: 'Failed to archive app "$appId".',
    );
    if (archiveError != null) return archiveError;

    if (isJsonMode) {
      emitJsonSuccess({'app_id': appId, 'archived': true});
      return ExitCode.success.code;
    }

    logger.success('Archived app "$appId".');
    return ExitCode.success.code;
  }
}
