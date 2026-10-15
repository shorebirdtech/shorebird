import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_delete_command}
/// `shorebird apps delete`
/// Permanently delete an app and every artifact belonging to it.
/// {@endtemplate}
class AppsDeleteCommand extends ShorebirdCommand
    with AppScopedCommand, ConfirmDelete {
  /// {@macro apps_delete_command}
  AppsDeleteCommand() {
    addConfirmDeleteOptions();
    addAppScopeOptions();
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Permanently deletes an app.\n\n'
      'Every release and patch belonging to the app is permanently removed. '
      'This cannot be undone.\n\n'
      "In a terminal, asks you to type the app's display name to confirm. "
      'Pass --$yesArgName to skip the prompt; it is required when not running '
      'interactively (no terminal, CI, or --json).\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps delete --app-id <id> --yes --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    late final AppMetadata app;
    late final List<Release> releases;
    final fetchError = await guardApiCall(
      () async {
        app = await codePushClientWrapper.getApp(appId: appId);
        releases = await codePushClientWrapper.getReleases(appId: appId);
      },
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch app "$appId".',
    );
    if (fetchError != null) return fetchError;

    final platforms = <String>{
      for (final release in releases)
        ...release.platformStatuses.keys.map((platform) => platform.name),
    }.toList()..sort();

    final gateErrorCode = confirmDelete(
      name: app.displayName,
      description:
          'app "${app.displayName}" ($appId) and all of its releases and '
          'patches',
      style: DeleteConfirmationStyle.typeName,
    );
    if (gateErrorCode != null) return gateErrorCode;

    final deleteError = await guardApiCall(
      () => codePushClientWrapper.deleteApp(appId: appId),
      code: JsonErrorCode.softwareError,
      message: 'Failed to delete app "$appId".',
    );
    if (deleteError != null) return deleteError;

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
