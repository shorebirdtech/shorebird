import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/apps/apps_list_command.dart';
import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs_list_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts_list_command.dart';
import 'package:shorebird_cli/src/commands/usage_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
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
      verify(
        () => h.logger.err(
          '`shorebird enterprise usage` covers every organization in your '
          'enterprise, so it takes no organization id.',
        ),
      ).called(1);
      verify(
        () => h.logger.info(
          'Drop `enterprise`: run `shorebird usage --org-id <id>` for one '
          'organization.',
        ),
      ).called(1);
      verifyNever(
        () => h.codePushClientWrapper.getEnterpriseBilling(
          enterpriseId: any(named: 'enterpriseId'),
        ),
      );
    });

    group('refuses an organization id', () {
      for (final (args, line) in [
        (['members', 'list'], 'members list'),
        (['service-accounts', 'list'], 'service-accounts list'),
        (['audit-log', 'list'], 'audit-log list'),
        (['audit-log', 'export'], 'audit-log export'),
      ]) {
        test('on enterprise $line', () async {
          expect(
            await run(['enterprise', ...args, '42']),
            ExitCode.usage.code,
          );
          verify(
            () => h.logger.err(
              '`shorebird enterprise $line` covers every organization in '
              'your enterprise, so it takes no organization id.',
            ),
          ).called(1);
          verify(
            () => h.logger.info(
              'Drop `enterprise`: run `shorebird $line --org-id <id>` for '
              'one organization.',
            ),
          ).called(1);
        });
      }

      for (final noun in ['orgs', 'apps']) {
        test('on enterprise $noun list', () async {
          expect(
            await run(['enterprise', noun, 'list', '42']),
            ExitCode.usage.code,
          );
          verify(
            () => h.logger.err(
              '`shorebird enterprise $noun list` covers every organization '
              'in your enterprise, so it takes no organization id.',
            ),
          ).called(1);
          verify(
            () => h.logger.info(
              'Drop `enterprise`: run `shorebird $noun list` for the ones '
              'you can access.',
            ),
          ).called(1);
        });
      }

      test('given as --org-id', () async {
        expect(
          await run(['enterprise', 'members', 'list', '--org-id', '42']),
          ExitCode.usage.code,
        );
        verify(
          () => h.logger.err(
            '`shorebird enterprise members list` covers every organization '
            'in your enterprise, so it takes no --org-id.',
          ),
        ).called(1);
        verifyNever(
          () => h.codePushClientWrapper.getEnterpriseMembers(
            enterpriseId: any(named: 'enterpriseId'),
          ),
        );
      });
    });

    test('a missing member names the enterprise command', () async {
      expect(
        await run(['enterprise', 'members', 'remove']),
        ExitCode.usage.code,
      );
      verify(
        () => h.logger.err(
          'Name one member by email or user id: '
          'shorebird enterprise members remove bob@acme.com.',
        ),
      ).called(1);
      expect(
        await run(['enterprise', 'members', 'set-role', '--role', 'admin']),
        ExitCode.usage.code,
      );
      verify(
        () => h.logger.err(
          'Name one member by email or user id: '
          'shorebird enterprise members set-role bob@acme.com --role admin.',
        ),
      ).called(1);
    });

    test('takes each of its own options', () async {
      when(() => h.logger.level).thenReturn(Level.info);
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
      final filters = [
        '--app-id',
        'app-1',
        '--actor',
        '9',
        '--event',
        'enterprise_member.remove',
        '--start',
        '2026-10-01',
        '--end',
        '2026-10-21',
        '--order',
        'asc',
      ];
      for (final args in [
        ['members', 'list', '--guests'],
        ['guests', 'list'],
        ['orgs', 'list'],
        ['apps', 'list'],
        ['service-accounts', 'list'],
        ['usage'],
        ['audit-log', 'list', ...filters, '--limit', '5', '--cursor', 'c2'],
        ['audit-log', 'export', ...filters],
      ]) {
        expect(
          await run(['enterprise', ...args]),
          ExitCode.success.code,
          reason: args.join(' '),
        );
      }
    });

    test('its audit-log --event example is an enterprise event', () {
      final enterprise = h.run(EnterpriseCommand.new);
      final list = enterprise.subcommands['audit-log']!.subcommands['list']!;
      expect(
        list.argParser.options['event']!.help,
        contains('enterprise_member.remove'),
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

    test('shows no --org-id in help', () {
      final enterprise = h.run(EnterpriseCommand.new);
      for (final noun in enterprise.subcommands.values.toSet()) {
        final leaves = noun.subcommands.isEmpty
            ? [noun]
            : noun.subcommands.values.toSet();
        for (final leaf in leaves) {
          for (final name in ['org-id']) {
            final option = leaf.argParser.options[name];
            if (option == null) continue;
            expect(
              option.hide,
              isTrue,
              reason: '${noun.name} ${leaf.name} --$name',
            );
          }
          expect(
            leaf.argParser.usage,
            isNot(contains('--org-id')),
            reason: '${noun.name} ${leaf.name}',
          );
        }
      }
    });

    test('no command takes --enterprise', () {
      final commands = <ShorebirdCommand Function()>[
        OrgsListCommand.new,
        AppsListCommand.new,
        MembersListCommand.new,
        MembersSetRoleCommand.new,
        MembersRemoveCommand.new,
        AuditLogListCommand.new,
        AuditLogExportCommand.new,
        UsageCommand.new,
        ServiceAccountsListCommand.new,
      ];
      for (final create in commands) {
        final command = h.run(create);
        expect(
          command.argParser.options.containsKey('enterprise'),
          isFalse,
          reason: command.name,
        );
      }
      expect(
        h.run(MembersListCommand.new).description,
        contains('shorebird enterprise members'),
      );
    });
  });
}
