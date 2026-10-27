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
          '"release-bot" trusts no workflows. Add one with shorebird '
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
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['service_account_id'], 383);
      expect(data['id'], 7);
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
