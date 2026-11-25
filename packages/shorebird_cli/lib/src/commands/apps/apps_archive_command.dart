import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_archive_command}
/// `shorebird apps archive`
/// Stop an app serving patches, keeping its releases and patches.
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
      'Stops an app serving patches and takes it out of your app quota.\n\n'
      'Its releases, patches and artifacts are kept, and a device that '
      'checks in keeps the patch it has. Creating a release or a patch on an '
      'archived app is refused. Run "shorebird apps unarchive" to bring it '
      'back.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps archive --app-id <id> --json',
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

    final archiveError = await guardApiCall(
      () => codePushClientWrapper.archiveApp(appId: appId),
      code: JsonErrorCode.softwareError,
      message: 'Failed to archive app "$appId".',
    );
    if (archiveError != null) return archiveError;

    if (isJsonMode) {
      emitJsonSuccess({'app_id': appId, 'display_name': app.displayName});
      return ExitCode.success.code;
    }

    logger.success('Archived "${app.displayName}".');
    return ExitCode.success.code;
  }
}
