import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_rename_command}
/// `shorebird apps rename`
/// Change an app's display name.
/// {@endtemplate}
class AppsRenameCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro apps_rename_command}
  AppsRenameCommand() {
    argParser.addOption(
      'name',
      help:
          'The new display name for the app (e.g. "Acme Mobile"), up to '
          '${CommonArguments.appDisplayNameMaxLength} characters.',
      mandatory: true,
    );
    addAppScopeOptions();
  }

  @override
  String get name => 'rename';

  @override
  String get description =>
      "Changes an app's display name.\n\n"
      'Example output:\n'
      '  Renamed "Acme Mobile" to "Acme Consumer".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps rename --app-id <id> --name "Acme Consumer" --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final displayName = results['name'] as String;
    final nameError = CommonArguments.nameError(
      label: 'App display name',
      value: displayName,
      maxLength: CommonArguments.appDisplayNameMaxLength,
    );
    if (nameError != null) return reportError(message: nameError);

    late final AppMetadata app;
    final fetchError = await guardApiCall(
      () async => app = await codePushClientWrapper.getApp(appId: appId),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch app "$appId".',
    );
    if (fetchError != null) return fetchError;

    if (app.displayName == displayName) {
      final message = 'App "$appId" is already named "$displayName".';
      return reportError(message: message);
    }

    final renameError = await guardApiCall(
      () => codePushClientWrapper.updateApp(
        appId: appId,
        displayName: displayName,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to rename app "$appId".',
    );
    if (renameError != null) return renameError;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'from_name': app.displayName,
        'to_name': displayName,
      });
      return ExitCode.success.code;
    }

    logger.success('Renamed "${app.displayName}" to "$displayName".');
    return ExitCode.success.code;
  }
}
