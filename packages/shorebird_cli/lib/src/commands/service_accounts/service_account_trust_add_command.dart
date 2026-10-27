import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The directory GitHub Actions reads workflow files from.
const _workflowsDir = '.github/workflows/';

/// {@template service_account_trust_add_command}
/// `shorebird service-accounts trust add <name or id> --github-repo ...`
/// Let a GitHub Actions workflow sign in as a service account.
/// {@endtemplate}
class ServiceAccountTrustAddCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_trust_add_command}
  ServiceAccountTrustAddCommand() {
    argParser
      ..addOption(
        'github-repo',
        help: 'The repository whose workflow may sign in (e.g. "acme/app").',
        mandatory: true,
      )
      ..addOption(
        'workflow',
        help:
            'The workflow file, in $_workflowsDir (e.g. "release.yml" or '
            '"${_workflowsDir}release.yml").',
        mandatory: true,
      )
      ..addOption(
        'ref',
        help:
            'Only jobs on this ref: exact ("refs/heads/main") or a prefix '
            'ending in * ("refs/tags/*"). Defaults to any ref.',
      )
      ..addOption(
        'environment',
        help:
            'Only jobs in this GitHub environment (e.g. "production"). '
            'Defaults to any environment.',
      );
    addOrganizationScopeOption();
  }

  @override
  String get name => 'add';

  @override
  List<String> get aliases => const ['create'];

  @override
  String get invocation =>
      'shorebird service-accounts trust add <service account name or id> '
      '--github-repo <owner>/<repo> --workflow <file>';

  @override
  String get commandLine => 'shorebird service-accounts trust add';

  @override
  String get description =>
      'Lets a GitHub Actions workflow sign in as a service account with the '
      "job's own OIDC token, so CI stores no Shorebird key. The job needs "
      '`permissions: id-token: write`.\n\n'
      'Example output:\n'
      '  Added trust rule 7: acme/app .github/workflows/release.yml (ref '
      'refs/heads/main, any environment) may sign in as "release-bot".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts trust add release-bot --github-repo '
        'acme/app --workflow release.yml --json',
      )}';

  @override
  Future<int> run() async {
    final repo = (results['github-repo'] as String).split('/');
    if (repo.length != 2 || repo.any((part) => part.isEmpty)) {
      return reportError(
        message:
            '--github-repo must be <owner>/<repo>, e.g. --github-repo '
            'acme/app.',
      );
    }
    final workflow = results['workflow'] as String;
    final workflowPath = workflow.contains('/')
        ? workflow
        : '$_workflowsDir$workflow';

    final (:resolved, :errorCode) = await resolveServiceAccount(
      results.rest.firstOrNull,
    );
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    late final ServiceAccountTrustRule rule;
    final addError = await guardApiCall(
      () async =>
          rule = await codePushClientWrapper.createServiceAccountTrustRule(
            organizationId: account.organizationId,
            serviceAccountId: account.id,
            rule: CreateServiceAccountTrustRuleRequest(
              provider: TrustRuleProvider.github,
              repositoryOwner: repo[0],
              repositoryName: repo[1],
              workflowPath: workflowPath,
              environment: results['environment'] as String?,
              refPattern: results['ref'] as String?,
            ),
          ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to add a trust rule to "${account.name}".',
    );
    if (addError != null) return addError;

    if (isJsonMode) {
      emitJsonSuccess({
        'service_account_id': account.id,
        ...trustRuleJson(rule),
      });
      return ExitCode.success.code;
    }

    final github = rule.github;
    final environment = github.environment == null
        ? 'any environment'
        : 'environment ${github.environment}';
    logger.success(
      'Added trust rule ${rule.id}: ${github.repositoryOwner}/'
      '${github.repositoryName} ${github.workflowPath} (ref '
      '${github.refPattern ?? 'any'}, $environment) may sign in as '
      '"${account.name}".',
    );
    return ExitCode.success.code;
  }
}
