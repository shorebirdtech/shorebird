import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  late ServiceAccountTestContext context;

  setUpAll(() {
    registerFallbackValue(
      const CreateServiceAccountTrustRuleRequest(
        provider: TrustRuleProvider.github,
        repositoryOwner: '',
        repositoryName: '',
        workflowPath: '',
      ),
    );
  });

  setUp(() => context = ServiceAccountTestContext());

  group(ServiceAccountTrustListCommand, () {
    test('prints one line per rule', () async {
      expect(
        await context.runCommand(ServiceAccountTrustListCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      const line =
          '7  acme/app  .github/workflows/release.yml  ref refs/heads/main  '
          'environment any  last used 2026-10-20';
      expect(context.infoLines, [line]);
    });

    test('says how to add one when there are none', () async {
      when(
        () => context.wrapper.getServiceAccountTrustRules(
          organizationId: 42,
          serviceAccountId: 383,
        ),
      ).thenAnswer((_) async => []);
      await context.runCommand(ServiceAccountTrustListCommand(), [
        'release-bot',
        '--org-id',
        '42',
      ]);
      const message =
          '"release-bot" trusts no workflows. Add one with shorebird orgs '
          'service-accounts trust add release-bot --github-repo '
          '<owner>/<repo> --workflow <file>.';
      expect(context.infoLines, [message]);
    });

    test('--json emits the rules', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountTrustListCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect((json['data'] as Map)['trust_rules'], hasLength(1));
    });
  });

  group(ServiceAccountTrustAddCommand, () {
    setUp(() {
      when(
        () => context.wrapper.createServiceAccountTrustRule(
          organizationId: 42,
          serviceAccountId: 383,
          rule: any(named: 'rule'),
        ),
      ).thenAnswer((_) async => releaseRule);
    });

    test('adds a rule, completing a bare workflow file name', () async {
      expect(
        await context.runCommand(ServiceAccountTrustAddCommand(), [
          'release-bot',
          '--github-repo',
          'acme/app',
          '--workflow',
          'release.yml',
          '--ref',
          'refs/heads/main',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.wrapper.createServiceAccountTrustRule(
          organizationId: 42,
          serviceAccountId: 383,
          rule: const CreateServiceAccountTrustRuleRequest(
            provider: TrustRuleProvider.github,
            repositoryOwner: 'acme',
            repositoryName: 'app',
            workflowPath: '.github/workflows/release.yml',
            refPattern: 'refs/heads/main',
          ),
        ),
      ).called(1);
      verify(
        () => context.logger.success(
          'Added trust rule 7: acme/app .github/workflows/release.yml (ref '
          'refs/heads/main, any environment) may sign in as "release-bot".',
        ),
      ).called(1);
    });

    test('keeps a workflow path and sends --environment', () async {
      await context.runCommand(ServiceAccountTrustAddCommand(), [
        'release-bot',
        '--github-repo',
        'acme/app',
        '--workflow',
        '.github/workflows/ship.yaml',
        '--environment',
        'production',
        '--org-id',
        '42',
      ]);
      verify(
        () => context.wrapper.createServiceAccountTrustRule(
          organizationId: 42,
          serviceAccountId: 383,
          rule: const CreateServiceAccountTrustRuleRequest(
            provider: TrustRuleProvider.github,
            repositoryOwner: 'acme',
            repositoryName: 'app',
            workflowPath: '.github/workflows/ship.yaml',
            environment: 'production',
          ),
        ),
      ).called(1);
    });

    Future<int> add(List<String> args) => context.runCommand(
      ServiceAccountTrustAddCommand(),
      [
        'release-bot',
        '--github-repo',
        'acme/app',
        '--workflow',
        'release.yml',
        ...args,
        '--org-id',
        '42',
      ],
    );

    CreateServiceAccountTrustRuleRequest sentRule() =>
        verify(
              () => context.wrapper.createServiceAccountTrustRule(
                organizationId: 42,
                serviceAccountId: 383,
                rule: captureAny(named: 'rule'),
              ),
            ).captured.single
            as CreateServiceAccountTrustRuleRequest;

    test('says what the workflow needs to sign in', () async {
      await add(['--ref', 'refs/heads/main']);
      verify(
        () => context.logger.info(
          'For the job to sign in, give it these in '
          '.github/workflows/release.yml:\n'
          '  permissions:\n'
          '    id-token: write\n'
          '  env:\n'
          '    SHOREBIRD_PROJECT_ID: 42',
        ),
      ).called(1);
    });

    test('requires --ref or --environment before any request', () async {
      expect(await add([]), ExitCode.usage.code);
      verify(
        () => context.logger.err(
          'Limit the rule with --ref (e.g. --ref main) or --environment '
          '(e.g. --environment production).',
        ),
      ).called(1);
      verifyNever(() => context.wrapper.getOrganizationMemberships());
    });

    test('--any-ref sends no ref and warns what it allows', () async {
      expect(await add(['--any-ref']), context.ok);
      expect(sentRule().refPattern, isNull);
      verify(
        () => context.logger.warn(
          'Any branch of acme/app whose .github/workflows/release.yml runs, '
          'including one pushed with an edited workflow, will sign in as '
          '"release-bot".',
        ),
      ).called(1);
    });

    test('a bare branch becomes refs/heads/<branch>', () async {
      await add(['--ref', 'main']);
      expect(sentRule().refPattern, 'refs/heads/main');
    });

    test('a ref for every ref needs --any-ref', () async {
      expect(await add(['--ref', '*']), ExitCode.usage.code);
      expect(await add(['--ref', 'refs/*']), ExitCode.usage.code);
      verify(
        () => context.logger.err(
          '--ref refs/* matches every ref. Pass --any-ref instead if that is '
          'what you mean.',
        ),
      ).called(1);
      expect(await add(['--ref', 'refs/*', '--any-ref']), context.ok);
      expect(sentRule().refPattern, isNull);
    });

    test('rejects --ref with --any-ref', () async {
      expect(await add(['--ref', 'main', '--any-ref']), ExitCode.usage.code);
      verify(
        () => context.logger.err('Pass --ref or --any-ref, not both.'),
      ).called(1);
    });

    test('rejects a wildcard that is not a full ref', () async {
      expect(await add(['--ref', 'v*']), ExitCode.usage.code);
    });

    test('warns when a wildcard over-matches', () async {
      await add(['--ref', 'refs/heads/main*']);
      verify(
        () => context.logger.warn(
          '--ref refs/heads/main* matches every ref that starts with '
          'refs/heads/main, not only one branch or tag.',
        ),
      ).called(1);
    });

    test('takes a pasted GitHub URL or .git suffix', () async {
      for (final repo in [
        ' https://github.com/acme/app/ ',
        'github.com/acme/app.git',
        'acme/app.git',
      ]) {
        await context.runCommand(ServiceAccountTrustAddCommand(), [
          'release-bot',
          '--github-repo',
          repo,
          '--workflow',
          'release.yml',
          '--ref',
          'main',
          '--org-id',
          '42',
        ]);
        final rule = sentRule();
        expect((rule.repositoryOwner, rule.repositoryName), ('acme', 'app'));
      }
    });

    test('rejects a second service account before any request', () async {
      expect(
        await context.runCommand(ServiceAccountTrustAddCommand(), [
          'release-bot',
          'deploy-bot',
          '--github-repo',
          'acme/app',
          '--workflow',
          'release.yml',
          '--ref',
          'main',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(() => context.wrapper.getOrganizationMemberships());
    });

    test('adds nothing when the name matches two accounts', () async {
      final shadow = ServiceAccount(
        id: 9,
        organizationId: 42,
        name: '383',
        label: '383[bot]',
        role: ServiceAccountRole.developer,
        createdAt: DateTime.utc(2026),
        createdByUserId: null,
        createdByEmail: null,
        lastAuthAt: null,
      );
      when(
        () => context.wrapper.getServiceAccounts(organizationId: 42),
      ).thenAnswer((_) async => [releaseBot, shadow]);
      expect(
        await context.runCommand(ServiceAccountTrustAddCommand(), [
          '383',
          '--github-repo',
          'acme/app',
          '--workflow',
          'release.yml',
          '--ref',
          'main',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(
        () => context.wrapper.createServiceAccountTrustRule(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
          rule: any(named: 'rule'),
        ),
      );
    });

    test('rejects a repo that is not owner/repo', () async {
      for (final repo in ['acme', 'acme/', 'acme/app/x']) {
        expect(
          await context.runCommand(ServiceAccountTrustAddCommand(), [
            'release-bot',
            '--github-repo',
            repo,
            '--workflow',
            'release.yml',
          ]),
          ExitCode.usage.code,
        );
      }
      verify(
        () => context.logger.err(
          '--github-repo must be <owner>/<repo>, e.g. --github-repo acme/app.',
        ),
      ).called(3);
    });

    test('reports a refused rule', () async {
      when(
        () => context.wrapper.createServiceAccountTrustRule(
          organizationId: 42,
          serviceAccountId: 383,
          rule: any(named: 'rule'),
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountTrustAddCommand(), [
          'release-bot',
          '--github-repo',
          'acme/app',
          '--workflow',
          'release.yml',
          '--ref',
          'main',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to add a trust rule to "release-bot".',
      );
    });

    test('--json emits the rule', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountTrustAddCommand(), [
          'release-bot',
          '--github-repo',
          'acme/app',
          '--workflow',
          'release.yml',
          '--ref',
          'main',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['service_account_id'], 383);
      expect(data['id'], 7);
      expect(data['repository_owner_id'], 1);
      expect(data['shorebird_project_id'], 42);
    });
  });

  group(ServiceAccountTrustRemoveCommand, () {
    setUp(() {
      when(
        () => context.wrapper.deleteServiceAccountTrustRule(
          organizationId: 42,
          serviceAccountId: 383,
          ruleId: 7,
        ),
      ).thenAnswer((_) async {});
    });

    test('rejects a third argument before any request', () async {
      expect(
        await context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '7',
          '8',
          '--yes',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(() => context.wrapper.getOrganizationMemberships());
    });

    test('removes the rule with --yes', () async {
      expect(
        await context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '7',
          '--yes',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.logger.success(
          'Removed trust rule 7 (acme/app .github/workflows/release.yml) from '
          '"release-bot".',
        ),
      ).called(1);
    });

    test('asks for the rule id and lists the rules', () async {
      expect(
        await context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.info(
          'Trust rules of "release-bot": 7 (acme/app '
          '.github/workflows/release.yml).',
        ),
      ).called(1);
    });

    test('names an unknown rule', () async {
      expect(
        await context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '8',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err('"release-bot" has no trust rule 8.'),
      ).called(1);
    });

    test('needs --yes when it cannot prompt', () async {
      expect(
        await context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '7',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(
        () => context.wrapper.deleteServiceAccountTrustRule(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
          ruleId: any(named: 'ruleId'),
        ),
      );
    });

    test('--json emits what it removed', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountTrustRemoveCommand(), [
          'release-bot',
          '7',
          '--yes',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect(json['data'], {'service_account_id': 383, 'rule_id': 7});
    });
  });
}
