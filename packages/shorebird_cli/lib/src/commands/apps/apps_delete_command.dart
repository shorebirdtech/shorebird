import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_delete_command}
/// `shorebird apps delete`
/// Opens the console page where an app is deleted.
/// {@endtemplate}
class AppsDeleteCommand extends ShorebirdCommand
    with AppScopedCommand, FinishInConsole {
  /// {@macro apps_delete_command}
  AppsDeleteCommand() {
    addAppScopeOptions();
    // Earlier versions deleted from the CLI and took these to confirm it.
    // Accept them so a script that passes one gets the console URL rather
    // than an unknown-option error.
    argParser
      ..addOption(confirmNameArgName, hide: true)
      ..addFlag(yesArgName, abbr: 'y', negatable: false, hide: true);
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      "Opens the app's settings in the Shorebird console, where you can "
      'delete it.\n\n'
      'Deleting an app permanently removes every release and patch, and '
      'devices running it stop getting patches, so it is confirmed by a '
      'person in the console rather than run from the CLI. When not running '
      'interactively (no terminal, CI, or --json), this prints the console '
      'URL and exits with an error.';

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

    return finishInConsole(
      action: 'delete app "${app.displayName}" ($appId)',
      url: ShorebirdWebConsole.appSettingsUri(
        organizationId: app.organizationId,
        appId: appId,
      ),
    );
  }
}
