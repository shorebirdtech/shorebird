import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_accounts_list_command}
/// `shorebird service-accounts list`
/// List an organization's service accounts.
/// {@endtemplate}
class ServiceAccountsListCommand extends ShorebirdCommand
    with OrganizationScopedCommand, EnterpriseScopedCommand {
  /// {@macro service_accounts_list_command}
  ServiceAccountsListCommand() {
    addOrganizationScopeOption();
    addEnterpriseScopeOption(
      help:
          'List the service accounts of every organization in this '
          'enterprise (e.g. "7") instead. Needs an owner or admin of the '
          'enterprise.',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      "Lists an organization's service accounts.\n\n"
      'Example output (space-separated: id  name  role  last signed in):\n'
      '  383  release-bot  developer  2026-10-20\n\n'
      "With --enterprise-id, lists every organization's service accounts "
      '(space-separated: id  name  organization_id  organization_name  role  '
      'last signed in). '
      'They stay owned by their organization; manage one with --org-id.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts list --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final scopeError = rejectOrganizationAndEnterprise();
    if (scopeError != null) return scopeError;
    if (enterpriseIdOption != null) return _listEnterpriseServiceAccounts();

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
        'shorebird service-accounts create <name>.',
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

  Future<int> _listEnterpriseServiceAccounts() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final List<EnterpriseServiceAccount> accounts;
    late final Map<int, String> organizationNames;
    final fetchError = await guardApiCall(
      () async {
        accounts = await codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: enterprise.id,
        );
        final organizations = await codePushClientWrapper
            .getEnterpriseOrganizations(enterpriseId: enterprise.id);
        organizationNames = {for (final o in organizations) o.id: o.name};
      },
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the service accounts of "${enterprise.name}".',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'service_accounts': [
          for (final account in accounts)
            enterpriseServiceAccountJson(
              account,
              organizationName: organizationNames[account.teamId],
            ),
        ],
      });
      return ExitCode.success.code;
    }

    if (accounts.isEmpty) {
      logger.info('"${enterprise.name}" has no service accounts.');
      return ExitCode.success.code;
    }
    for (final account in accounts) {
      final organization = organizationNames[account.teamId] ?? '-';
      logger.info(
        '${account.userId}  ${lightCyan.wrap(account.name)}  '
        '${account.teamId}  $organization  ${account.role.value}  '
        '${formatDate(account.lastAuthAt)}',
      );
    }
    return ExitCode.success.code;
  }
}
