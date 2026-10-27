import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_accounts_delete_command}
/// `shorebird orgs service-accounts delete <name or id>`
/// Delete a service account, with its keys and trust rules.
/// {@endtemplate}
class ServiceAccountsDeleteCommand extends ShorebirdCommand
    with ConfirmDelete, OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_accounts_delete_command}
  ServiceAccountsDeleteCommand() {
    addConfirmDeleteOptions(deprecatedConfirmName: false);
    addOrganizationScopeOption();
  }

  @override
  String get name => 'delete';

  @override
  String get invocation =>
      'shorebird orgs service-accounts delete <name or id>';

  @override
  String get commandLine => 'shorebird orgs service-accounts delete';

  @override
  String get description =>
      'Deletes a service account, with its keys and trust rules, so CI that '
      'uses them stops signing in. This cannot be undone.\n\n'
      'Example output:\n'
      '  Deleted service account "release-bot".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts delete release-bot --org-id 42 --yes '
        '--json',
      )}';

  @override
  Future<int> run() async {
    final (:resolved, :errorCode) = await resolveServiceAccount();
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    final confirmError = confirmDelete(
      name: account.name,
      description: 'service account "${account.name}"',
      consequence:
          'Deleting "${account.name}" revokes its keys and trust rules, so '
          'CI that uses them stops signing in.',
    );
    if (confirmError != null) return confirmError;

    final deleteError = await guardApiCall(
      () => codePushClientWrapper.deleteServiceAccount(
        organizationId: account.organizationId,
        serviceAccountId: account.id,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to delete service account "${account.name}".',
    );
    if (deleteError != null) return deleteError;

    if (isJsonMode) {
      emitJsonSuccess({'id': account.id, 'name': account.name});
      return ExitCode.success.code;
    }

    logger.success('Deleted service account "${account.name}".');
    return ExitCode.success.code;
  }
}
