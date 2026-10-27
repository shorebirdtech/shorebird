import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_accounts_list_command}
/// `shorebird orgs service-accounts list`
/// List an organization's service accounts.
/// {@endtemplate}
class ServiceAccountsListCommand extends ShorebirdCommand
    with OrganizationScopedCommand {
  /// {@macro service_accounts_list_command}
  ServiceAccountsListCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      "Lists an organization's service accounts.\n\n"
      'Example output (space-separated: id  name  role  last signed in):\n'
      '  383  release-bot  developer  2026-10-20\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts list --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final List<ServiceAccount> accounts;
    final fetchError = await guardApiCall(
      () async => accounts = await codePushClientWrapper.getServiceAccounts(
        organizationId: organization.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the service accounts of "${organization.name}".',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'service_accounts': accounts.map(serviceAccountJson).toList(),
      });
      return ExitCode.success.code;
    }

    if (accounts.isEmpty) {
      logger.info(
        '"${organization.name}" has no service accounts. Create one with '
        'shorebird orgs service-accounts create <name>.',
      );
      return ExitCode.success.code;
    }

    for (final account in accounts) {
      logger.info(
        '${account.id}  ${lightCyan.wrap(account.name)}  '
        '${account.role.value}  ${formatDate(account.lastAuthAt)}',
      );
    }
    return ExitCode.success.code;
  }
}
