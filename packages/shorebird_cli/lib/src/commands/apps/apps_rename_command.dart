import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_rename_command}
/// `shorebird apps rename`
/// Change an app's display name.
/// {@endtemplate}
class AppsRenameCommand extends ShorebirdCommand {
  /// {@macro apps_rename_command}
  AppsRenameCommand() {
    argParser
      ..addOption(
        'name',
        help: 'The new display name for the app (e.g. "Acme Mobile").',
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
    if (displayName.trim().isEmpty) {
      const message = 'The new name must not be empty.';
      if (isJsonMode) {
        emitJsonError(code: JsonErrorCode.usageError, message: message);
        return ExitCode.usage.code;
      }
      logger.err(message);
      return ExitCode.usage.code;
    }

    final AppMetadata app;
    try {
      app = await codePushClientWrapper.getApp(appId: appId);
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

    if (app.displayName == displayName) {
      final message = 'App "$appId" is already named "$displayName".';
      if (isJsonMode) {
        emitJsonError(code: JsonErrorCode.usageError, message: message);
        return ExitCode.usage.code;
      }
      logger.err(message);
      return ExitCode.usage.code;
    }

    try {
      await codePushClientWrapper.updateApp(
        appId: appId,
        displayName: displayName,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message: 'Failed to rename app "$appId".',
        );
        return e.exitCode;
      }
      rethrow;
    }

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
