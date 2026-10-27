import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_account_trust_remove_command}
/// `shorebird orgs service-accounts trust remove <name or id> <rule id>`
/// Stop a workflow from signing in as a service account.
/// {@endtemplate}
class ServiceAccountTrustRemoveCommand extends ShorebirdCommand
    with ConfirmDelete, OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_trust_remove_command}
  ServiceAccountTrustRemoveCommand() {
    addConfirmDeleteOptions(deprecatedConfirmName: false);
    addOrganizationScopeOption();
  }

  @override
  String get name => 'remove';

  @override
  List<String> get aliases => const ['delete'];

  @override
  String get invocation =>
      'shorebird orgs service-accounts trust remove '
      '<service account name or id> <rule id>';

  @override
  String get commandLine => 'shorebird orgs service-accounts trust remove';

  @override
  int get maxArguments => 2;

  @override
  String get description =>
      'Removes a trust rule, so its workflow can no longer sign in as the '
      'service account.\n\n'
      'Example output:\n'
      '  Removed trust rule 7 (acme/app .github/workflows/release.yml) from '
      '"release-bot".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts trust remove release-bot 7 '
        '--org-id 42 --yes --json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    final (:resolved, :errorCode) = await resolveServiceAccount();
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    late final List<ServiceAccountTrustRule> rules;
    final fetchError = await guardApiCall(
      () async =>
          rules = await codePushClientWrapper.getServiceAccountTrustRules(
            organizationId: account.organizationId,
            serviceAccountId: account.id,
          ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the trust rules of "${account.name}".',
    );
    if (fetchError != null) return fetchError;

    final ruleIdArg = rest.length > 1 ? rest[1] : null;
    final ruleId = ruleIdArg == null ? null : int.tryParse(ruleIdArg);
    final rule = rules.firstWhereOrNull((r) => r.id == ruleId);
    if (rule == null) {
      final hint = rules.isEmpty
          ? '"${account.name}" has no trust rules.'
          : 'Trust rules of "${account.name}": '
                '${rules.map((r) => '${r.id} (${_describe(r)})').join(', ')}.';
      return reportError(
        message: ruleIdArg == null
            ? 'Name the rule to remove: $commandLine '
                  '${shellQuote(account.name)} <rule id>.'
            : '"${account.name}" has no trust rule $ruleIdArg.',
        hint: hint,
      );
    }

    final confirmError = confirmDelete(
      name: '${rule.id}',
      description: 'trust rule ${rule.id} (${_describe(rule)})',
      consequence:
          '${_describe(rule)} will no longer sign in as "${account.name}".',
    );
    if (confirmError != null) return confirmError;

    final removeError = await guardApiCall(
      () => codePushClientWrapper.deleteServiceAccountTrustRule(
        organizationId: account.organizationId,
        serviceAccountId: account.id,
        ruleId: rule.id,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to remove trust rule ${rule.id} from "${account.name}".',
    );
    if (removeError != null) return removeError;

    if (isJsonMode) {
      emitJsonSuccess({'service_account_id': account.id, 'rule_id': rule.id});
      return ExitCode.success.code;
    }

    logger.success(
      'Removed trust rule ${rule.id} (${_describe(rule)}) from '
      '"${account.name}".',
    );
    return ExitCode.success.code;
  }
}

String _describe(ServiceAccountTrustRule rule) =>
    '${rule.github.repositoryOwner}/${rule.github.repositoryName} '
    '${rule.github.workflowPath}';
