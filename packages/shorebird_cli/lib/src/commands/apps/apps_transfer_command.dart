import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_transfer_command}
/// `shorebird apps transfer`
/// Move an app into a different organization.
/// {@endtemplate}
class AppsTransferCommand extends ShorebirdCommand {
  /// {@macro apps_transfer_command}
  AppsTransferCommand() {
    argParser
      ..addOption(
        'org-id',
        help: 'The id of the organization to move the app into (e.g. "42").',
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
  String get name => 'transfer';

  @override
  String get description =>
      'Moves an app into a different organization.\n\n'
      "You must be able to transfer apps out of the app's current "
      'organization as well as into the target one. Run '
      '"shorebird account orgs" to list the organizations you belong to.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird apps transfer --app-id <id> --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final orgIdArg = results['org-id'] as String;
    final organizationId = int.tryParse(orgIdArg);
    if (organizationId == null) {
      final message = '"$orgIdArg" is not a valid organization id.';
      const hint = 'Organization ids are integers, e.g. --org-id 42.';
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: message,
          hint: hint,
        );
        return ExitCode.usage.code;
      }
      logger
        ..err(message)
        ..info(hint);
      return ExitCode.usage.code;
    }

    final AppMetadata app;
    final List<OrganizationMembership> memberships;
    try {
      app = await codePushClientWrapper.getApp(appId: appId);
      memberships = await codePushClientWrapper.getOrganizationMemberships();
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

    // Catch a wrong org id before the write, so the failure names the
    // organization the caller is not in rather than surfacing a generic
    // permission error.
    final membership = memberships.firstWhereOrNull(
      (m) => m.organization.id == organizationId,
    );
    if (membership == null) {
      final message = 'You are not a member of organization $organizationId.';
      const hint = 'Run: shorebird account orgs';
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: message,
          hint: hint,
        );
        return ExitCode.usage.code;
      }
      logger
        ..err(message)
        ..info(hint);
      return ExitCode.usage.code;
    }

    final organizationName = membership.organization.name;

    try {
      await codePushClientWrapper.transferApp(
        organizationId: organizationId,
        appId: appId,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message: 'Failed to transfer app "$appId".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (isJsonMode) {
      // The source organization is resolved server-side; AppMetadata does not
      // carry it, and finding it here would mean walking every organization.
      emitJsonSuccess({
        'app_id': appId,
        'display_name': app.displayName,
        'to_organization_id': organizationId,
        'to_organization_name': organizationName,
      });
      return ExitCode.success.code;
    }

    logger.success('Moved "${app.displayName}" into "$organizationName".');
    return ExitCode.success.code;
  }
}
