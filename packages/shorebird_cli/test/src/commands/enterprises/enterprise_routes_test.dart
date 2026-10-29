import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'enterprise_fixtures.dart';
import 'enterprise_test_harness.dart';

/// Runs real command lines through `shorebird enterprise`, to check each
/// noun under it reaches the enterprise path of the command it shares.
void main() {
  useTempWorkingDirectory();

  group('shorebird enterprise', () {
    late EnterpriseHarness h;

    setUp(() {
      h = EnterpriseHarness();
      when(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).thenAnswer((_) async => [EnterpriseFixtures.member()]);
      when(
        () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
      ).thenAnswer((_) async => []);
      when(
        () =>
            h.codePushClientWrapper.getEnterpriseOrganizations(enterpriseId: 7),
      ).thenAnswer((_) async => []);
      when(
        () => h.codePushClientWrapper.getEnterpriseApps(enterpriseId: 7),
      ).thenAnswer((_) async => []);
      when(
        () => h.codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: 7,
        ),
      ).thenAnswer((_) async => []);
      when(
        () => h.codePushClientWrapper.getEnterpriseAuditLogs(
          enterpriseId: 7,
          perPage: any(named: 'perPage'),
          cursor: any(named: 'cursor'),
          order: any(named: 'order'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          appId: any(named: 'appId'),
          actorId: any(named: 'actorId'),
          operation: any(named: 'operation'),
        ),
      ).thenAnswer(
        (_) async => const GetOrganizationAuditLogsResponse(data: []),
      );
      when(
        () => h.codePushClientWrapper.getEnterpriseBilling(enterpriseId: 7),
      ).thenAnswer(
        (_) async => EnterpriseBilling.fromJson(const {
          'has_billing_account': false,
          'plan': null,
          'position': null,
        }),
      );
    });

    Future<int?> run(List<String> args, {Command<int>? command}) => h.run(
      () => (CommandRunner<int>(
        'shorebird',
        '',
      )..addCommand(command ?? EnterpriseCommand())).run(args),
    );

    test('members list reads the directory', () async {
      expect(
        await run(['enterprise', 'members', 'list']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).called(1);
    });

    test('members list --guests reads the guests', () async {
      expect(
        await run(['enterprise', 'members', 'list', '--guests']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
      ).called(1);
    });

    test('guests list reads the guests', () async {
      expect(
        await run(['enterprises', 'guests', 'list']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
      ).called(1);
    });

    test('members set-role changes the enterprise role', () async {
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acmeOwner]);
      when(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: 7,
          userId: 9,
          role: EnterpriseRole.admin,
        ),
      ).thenAnswer((_) async {});
      expect(
        await run([
          'enterprise',
          'members',
          'set-role',
          'bob@acme.com',
          '--role',
          'admin',
        ]),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: 7,
          userId: 9,
          role: EnterpriseRole.admin,
        ),
      ).called(1);
    });

    test('members remove hands off to the console', () async {
      when(() => h.shorebirdEnv.canAcceptUserInput).thenReturn(false);
      expect(
        await run(['enterprise', 'members', 'remove', 'bob@acme.com']),
        ExitCode.unavailable.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).called(1);
    });

    test('orgs list lists every organization', () async {
      expect(
        await run(['enterprise', 'orgs', 'list']),
        ExitCode.success.code,
      );
      verify(
        () =>
            h.codePushClientWrapper.getEnterpriseOrganizations(enterpriseId: 7),
      ).called(1);
    });

    test('apps list lists every app', () async {
      expect(
        await run(['enterprise', 'apps', 'list']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseApps(enterpriseId: 7),
      ).called(1);
    });

    test('audit-log list reads the enterprise log', () async {
      expect(
        await run(['enterprise', 'audit-log', 'list', '--since', '2026-10-21']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseAuditLogs(
          enterpriseId: 7,
          order: AuditLogOrder.desc,
          startDate: DateTime.utc(2026, 10, 21),
        ),
      ).called(1);
    });

    test('usage reads the enterprise billing', () async {
      expect(await run(['enterprise', 'usage']), ExitCode.success.code);
      verify(
        () => h.codePushClientWrapper.getEnterpriseBilling(enterpriseId: 7),
      ).called(1);
    });

    test('usage refuses an organization id', () async {
      expect(await run(['enterprise', 'usage', '42']), ExitCode.usage.code);
      verifyNever(
        () => h.codePushClientWrapper.getEnterpriseBilling(
          enterpriseId: any(named: 'enterpriseId'),
        ),
      );
    });

    test('service-accounts list lists every organization', () async {
      expect(
        await run(['enterprise', 'service-accounts', 'list']),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseServiceAccounts(
          enterpriseId: 7,
        ),
      ).called(1);
    });

    test('takes no --org-id or --enterprise', () {
      final enterprise = h.run(EnterpriseCommand.new);
      for (final noun in enterprise.subcommands.values.toSet()) {
        final leaves = noun.subcommands.isEmpty
            ? [noun]
            : noun.subcommands.values.toSet();
        for (final leaf in leaves) {
          expect(
            leaf.argParser.options.keys,
            isNot(anyOf(contains('org-id'), contains('enterprise'))),
            reason: '${noun.name} ${leaf.name}',
          );
        }
      }
    });

    test('the hidden --enterprise flag still works', () async {
      expect(
        await run([
          'members',
          'list',
          '--enterprise',
        ], command: MembersCommand()),
        ExitCode.success.code,
      );
      verify(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).called(1);
    });

    test('the top-level help hides --enterprise', () {
      final command = h.run(MembersListCommand.new);
      expect(command.argParser.usage, isNot(contains('--enterprise')));
      expect(command.description, contains('shorebird enterprise members'));
    });
  });
}
