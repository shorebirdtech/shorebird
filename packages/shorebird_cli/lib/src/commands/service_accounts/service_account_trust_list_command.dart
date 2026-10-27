import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_account_trust_list_command}
/// `shorebird orgs service-accounts trust list <name or id>`
/// List the workflows a service account trusts.
/// {@endtemplate}
class ServiceAccountTrustListCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_trust_list_command}
  ServiceAccountTrustListCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'list';

  @override
  String get invocation =>
      'shorebird orgs service-accounts trust list <service account name or id>';

  @override
  String get commandLine => 'shorebird orgs service-accounts trust list';

  @override
  String get description =>
      "Lists a service account's trust rules: the GitHub Actions workflows "
      'that may sign in as it.\n\n'
      'Example output (space-separated: id  repository  workflow  ref  '
      'environment  last used):\n'
      '  7  acme/app  .github/workflows/release.yml  ref refs/heads/main  '
      'environment any  last used 2026-10-20\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts trust list release-bot --org-id 42 '
        '--json',
      )}';

  @override
  Future<int> run() async {
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

    if (isJsonMode) {
      emitJsonSuccess({
        'service_account_id': account.id,
        'trust_rules': rules.map(trustRuleJson).toList(),
      });
      return ExitCode.success.code;
    }

    if (rules.isEmpty) {
      logger.info(
        '"${account.name}" trusts no workflows. Add one with shorebird orgs '
        'service-accounts trust add ${shellQuote(account.name)} --github-repo '
        '<owner>/<repo> --workflow <file>.',
      );
      return ExitCode.success.code;
    }
    for (final rule in rules) {
      logger.info(trustRuleLine(rule));
    }
    return ExitCode.success.code;
  }
}
