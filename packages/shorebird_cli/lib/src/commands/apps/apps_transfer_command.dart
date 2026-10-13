import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/organization_id.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_transfer_command}
/// `shorebird apps transfer`
/// Move an app into a different organization.
/// {@endtemplate}
class AppsTransferCommand extends ShorebirdCommand with AppScopedCommand {
  /// {@macro apps_transfer_command}
  AppsTransferCommand() {
    argParser.addOption(
      CommonArguments.orgIdArg.name,
      help: 'The id of the organization to move the app into (e.g. "42").',
      mandatory: true,
    );
    addAppScopeOptions();
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

    late final AppMetadata app;
    late final List<OrganizationMembership> memberships;
    final fetchError = await guardApiCall(
      () async {
        app = await codePushClientWrapper.getApp(appId: appId);
        memberships = await codePushClientWrapper.getOrganizationMemberships();
      },
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch app "$appId".',
    );
    if (fetchError != null) return fetchError;

    // Parsed after the fetch so an invalid id's hint can list the user's orgs.
    final (id: organizationId, error: parseError) = parseOrganizationId(
      results[CommonArguments.orgIdArg.name] as String,
      memberships: memberships,
    );
    if (parseError != null) {
      return reportError(message: parseError.message, hint: parseError.hint);
    }

    // Fail fast on an org the caller is not in, so the message can name it.
    final (:membership, error: membershipError) = findOrganizationMembership(
      id: organizationId!,
      memberships: memberships,
    );
    if (membershipError != null) {
      return reportError(
        message: membershipError.message,
        hint: membershipError.hint,
      );
    }

    final organizationName = membership!.organization.name;

    final transferError = await guardApiCall(
      () => codePushClientWrapper.transferApp(
        organizationId: organizationId,
        appId: appId,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to transfer app "$appId".',
    );
    if (transferError != null) return transferError;

    if (isJsonMode) {
      // AppMetadata does not carry the source organization, and finding it
      // here would mean walking every organization.
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
