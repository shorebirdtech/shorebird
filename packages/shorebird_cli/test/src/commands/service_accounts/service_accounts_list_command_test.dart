import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../enterprises/enterprise_fixtures.dart';
import '../enterprises/enterprise_test_harness.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  group(ServiceAccountsListCommand, () {
    late ServiceAccountTestContext context;

    setUp(() => context = ServiceAccountTestContext());

    test('prints one line per service account', () async {
      expect(
        await context.runCommand(ServiceAccountsListCommand(), [
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      expect(context.infoLines, [
        allOf(
          startsWith('383  '),
          contains('release-bot'),
          endsWith('  developer  2026-10-20'),
        ),
      ]);
    });

    test('says how to create one when there are none', () async {
      when(
        () => context.wrapper.getServiceAccounts(organizationId: 42),
      ).thenAnswer((_) async => []);
      await context.runCommand(ServiceAccountsListCommand(), [
        '--org-id',
        '42',
      ]);
      const message =
          '"Acme Corp" has no service accounts. Create one with shorebird '
          'service-accounts create <name>.';
      expect(context.infoLines, [message]);
    });

    test('--json emits every field', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsListCommand(), [
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect(json['data'], {
        'organization_id': 42,
        'service_accounts': [
          {
            'id': 383,
            'name': 'release-bot',
            'label': 'release-bot[bot]',
            'role': 'developer',
            'organization_id': 42,
            'created_at': '2026-10-01T00:00:00.000Z',
            'created_by_email': 'admin@acme.com',
            'last_auth_at': '2026-10-20T00:00:00.000Z',
          },
        ],
      });
    });
  });

  group('ServiceAccountsListCommand under shorebird enterprise', () {
    late EnterpriseHarness h;
    late ServiceAccountsListCommand command;

    final account = EnterpriseServiceAccount.fromJson(const {
      'user_id': 383,
      'name': 'release-bot',
      'team_id': 42,
      'role': 'developer',
      'created_at': '2026-10-01T00:00:00.000Z',
      'last_auth_at': '2026-10-20T09:00:00.000Z',
      'created_by_email': 'alice@acme.com',
    });

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => [account]);
      when(
        () => h.codePushClientWrapper.getEnterpriseOrganizations(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => [EnterpriseFixtures.mobile]);
      command = h.run(() => ServiceAccountsListCommand(enterpriseRoute: true));
    });

    void parse(List<String> args) =>
        command.testArgResults = command.argParser.parse(args);

    test("lists every organization's accounts", () async {
      parse([]);
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(
          startsWith('383  '),
          contains('release-bot'),
          endsWith('42  Mobile  developer  2026-10-20'),
        ),
      ]);
      verifyNever(
        () => h.codePushClientWrapper.getServiceAccounts(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('says when there are none', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => []);
      parse([]);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.info('"Acme" has no service accounts.'),
      ).called(1);
    });

    test("--json names each account's organization", () async {
      parse([]);
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'enterprise_id': 7,
        'service_accounts': [
          {
            'id': 383,
            'name': 'release-bot',
            'role': 'developer',
            'organization_id': 42,
            'organization_name': 'Mobile',
            'created_at': '2026-10-01T00:00:00.000Z',
            'created_by_email': 'alice@acme.com',
            'last_auth_at': '2026-10-20T09:00:00.000Z',
          },
        ],
      });
    });

    test('rejects --org-id', () async {
      parse(['--org-id', '42']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: 7,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      parse([]);
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the service accounts of "Acme".',
      );
    });
  });
}
