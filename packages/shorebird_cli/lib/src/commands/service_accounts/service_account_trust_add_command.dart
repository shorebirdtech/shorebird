import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/oidc_credential_source.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The directory GitHub Actions reads workflow files from.
const _workflowsDir = '.github/workflows/';

/// The flag that lets a rule match every ref.
const anyRefFlag = 'any-ref';

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
        help:
            'The repository whose workflow may sign in (e.g. "acme/app" or '
            '"https://github.com/acme/app").',
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
            'Only jobs on this ref: a branch ("main"), an exact ref '
            '("refs/heads/main") or a prefix ending in /* ("refs/tags/*"). '
            'Pass --ref, --environment or both.',
      )
      ..addOption(
        'environment',
        help:
            'Only jobs in this GitHub environment (e.g. "production"), whose '
            'protection rules then guard the sign-in.',
      )
      ..addFlag(
        anyRefFlag,
        negatable: false,
        help:
            'Let jobs on any ref sign in. Anyone who can push a branch can '
            'then edit the workflow on it and sign in, so prefer --ref or '
            '--environment.',
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
      '--github-repo <owner>/<repo> --workflow <file> --ref <ref>';

  @override
  String get commandLine => 'shorebird service-accounts trust add';

  @override
  String get description =>
      'Lets a GitHub Actions workflow sign in as a service account with the '
      "job's own OIDC token, so CI stores no Shorebird key. Limit the rule to "
      'a ref, a protected environment, or both: a job runs the copy of the '
      'workflow on its own branch, so a rule for any ref trusts anyone who '
      'can push a branch.\n\n'
      'Example output:\n'
      '  Added trust rule 7: acme/app .github/workflows/release.yml (ref '
      'refs/heads/main, any environment) may sign in as "release-bot".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts trust add release-bot --github-repo '
        'acme/app --workflow release.yml --ref main --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final repo = _parseRepo(results['github-repo'] as String);
    if (repo == null) {
      return reportError(
        message:
            '--github-repo must be <owner>/<repo>, e.g. --github-repo '
            'acme/app.',
      );
    }
    final workflow = (results['workflow'] as String).trim();
    final workflowPath = workflow.contains('/')
        ? workflow
        : '$_workflowsDir$workflow';
    final environment = (results['environment'] as String?)?.trim();
    final anyRef = results[anyRefFlag] as bool;

    final (:ref, error: refError) = _parseRef(
      results['ref'] as String?,
      anyRef: anyRef,
    );
    if (refError != null) return reportError(message: refError);
    if (ref == null && !anyRef && environment == null) {
      return reportError(
        message:
            'Limit the rule with --ref (e.g. --ref main) or --environment '
            '(e.g. --environment production).',
        hint:
            'A job runs the copy of the workflow on its own branch, so a rule '
            'for any ref lets anyone who can push a branch to '
            '${repo.owner}/${repo.name} sign in. Pass --$anyRefFlag to allow '
            'that anyway.',
      );
    }

    final (:resolved, :errorCode) = await resolveServiceAccount();
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    if (!isJsonMode) {
      if (anyRef && environment == null) {
        logger.warn(
          'Any branch of ${repo.owner}/${repo.name} whose $workflowPath runs, '
          'including one pushed with an edited workflow, will sign in as '
          '"${account.name}".',
        );
      }
      if (ref != null && ref.endsWith('*') && !ref.endsWith('/*')) {
        logger.warn(
          '--ref $ref matches every ref that starts with '
          '${ref.substring(0, ref.length - 1)}, not only one branch or tag.',
        );
      }
    }

    late final ServiceAccountTrustRule rule;
    final addError = await guardApiCall(
      () async =>
          rule = await codePushClientWrapper.createServiceAccountTrustRule(
            organizationId: account.organizationId,
            serviceAccountId: account.id,
            rule: CreateServiceAccountTrustRuleRequest(
              provider: TrustRuleProvider.github,
              repositoryOwner: repo.owner,
              repositoryName: repo.name,
              workflowPath: workflowPath,
              environment: environment,
              refPattern: ref,
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
        'shorebird_project_id': account.organizationId,
      });
      return ExitCode.success.code;
    }

    final github = rule.github;
    final environmentText = github.environment == null
        ? 'any environment'
        : 'environment ${github.environment}';
    logger
      ..success(
        'Added trust rule ${rule.id}: ${github.repositoryOwner}/'
        '${github.repositoryName} ${github.workflowPath} (ref '
        '${github.refPattern ?? 'any'}, $environmentText) may sign in as '
        '"${account.name}".',
      )
      ..info(
        'For the job to sign in, give it these in ${github.workflowPath}:\n'
        '  permissions:\n'
        '    id-token: write\n'
        '  env:\n'
        '    $shorebirdProjectIdEnvVar: ${account.organizationId}',
      );
    return ExitCode.success.code;
  }
}

/// Reads `owner/repo` from [value], also accepting a pasted GitHub URL and a
/// trailing `.git`, or null when it names no repository.
({String owner, String name})? _parseRepo(String value) {
  var repo = value.trim();
  repo = repo.replaceFirst(RegExp(r'^(https?://)?(www\.)?github\.com/'), '');
  repo = repo.replaceFirst(RegExp(r'/+$'), '');
  repo = repo.replaceFirst(RegExp(r'\.git$'), '');
  final parts = repo.split('/');
  if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
  return (owner: parts[0], name: parts[1]);
}

/// Turns `--ref` into the ref pattern the server matches against the token's
/// `ref` claim, which is always a full ref: a bare branch name becomes
/// `refs/heads/<name>`. A pattern for every ref is refused unless [anyRef],
/// and then sent as no pattern at all.
({String? ref, String? error}) _parseRef(
  String? value, {
  required bool anyRef,
}) {
  final ref = value?.trim();
  if (ref == null) return (ref: null, error: null);
  if (ref == '*' || ref == 'refs/*') {
    if (anyRef) return (ref: null, error: null);
    return (
      ref: null,
      error:
          '--ref $ref matches every ref. Pass --$anyRefFlag instead if that '
          'is what you mean.',
    );
  }
  if (anyRef) {
    return (
      ref: null,
      error: 'Pass --ref or --$anyRefFlag, not both.',
    );
  }
  if (ref.startsWith('refs/')) return (ref: ref, error: null);
  if (ref.contains('*')) {
    return (
      ref: null,
      error:
          '--ref $ref is not a full ref. Use refs/heads/<prefix>* for '
          'branches or refs/tags/<prefix>* for tags.',
    );
  }
  return (ref: 'refs/heads/$ref', error: null);
}
