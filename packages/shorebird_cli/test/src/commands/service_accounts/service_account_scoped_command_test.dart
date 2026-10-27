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

  // ServiceAccountsGetCommand is the simplest ServiceAccountScopedCommand,
  // so these cover how every such command finds its service account.
  group(ServiceAccountScopedCommand, () {
    late ServiceAccountTestContext context;

    setUp(() => context = ServiceAccountTestContext());

    test('finds the service account by id', () async {
      expect(
        await context.runCommand(ServiceAccountsGetCommand(), [
          '383',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
    });

    group('when the argument matches more than one account', () {
      ServiceAccount account({required int id, required String name}) =>
          ServiceAccount(
            id: id,
            organizationId: 42,
            name: name,
            label: '$name[bot]',
            role: ServiceAccountRole.developer,
            createdAt: DateTime.utc(2026),
            createdByUserId: null,
            createdByEmail: null,
            lastAuthAt: null,
          );

      Future<void> expectAmbiguous(
        List<ServiceAccount> accounts,
        String argument,
        String message,
      ) async {
        when(
          () => context.wrapper.getServiceAccounts(organizationId: 42),
        ).thenAnswer((_) async => accounts);
        when(
          () => context.wrapper.deleteServiceAccount(
            organizationId: any(named: 'organizationId'),
            serviceAccountId: any(named: 'serviceAccountId'),
          ),
        ).thenAnswer((_) async {});
        expect(
          await context.runCommand(ServiceAccountsDeleteCommand(), [
            argument,
            '--yes',
            '--org-id',
            '42',
          ]),
          ExitCode.usage.code,
        );
        verify(() => context.logger.err(message)).called(1);
        verifyNever(
          () => context.wrapper.deleteServiceAccount(
            organizationId: any(named: 'organizationId'),
            serviceAccountId: any(named: 'serviceAccountId'),
          ),
        );
      }

      test("an id and another account's name: acts on neither", () async {
        await expectAmbiguous(
          [releaseBot, account(id: 9, name: '383')],
          '383',
          '"383" matches 2 service accounts in "Acme Corp": release-bot '
              '(id: 383), 383 (id: 9).',
        );
        verify(
          () => context.logger.info(
            'Pick one by id, e.g. shorebird service-accounts delete '
            'id:383',
          ),
        ).called(1);
      });

      test('a name two accounts share: acts on neither', () async {
        await expectAmbiguous(
          [releaseBot, account(id: 400, name: 'release-bot')],
          'release-bot',
          '"release-bot" matches 2 service accounts in "Acme Corp": '
              'release-bot (id: 383), release-bot (id: 400).',
        );
      });

      test('id:<id> picks one', () async {
        when(
          () => context.wrapper.getServiceAccounts(organizationId: 42),
        ).thenAnswer((_) async => [releaseBot, account(id: 9, name: '383')]);
        when(
          () => context.wrapper.deleteServiceAccount(
            organizationId: 42,
            serviceAccountId: 9,
          ),
        ).thenAnswer((_) async {});
        expect(
          await context.runCommand(ServiceAccountsDeleteCommand(), [
            'id:9',
            '--yes',
            '--org-id',
            '42',
          ]),
          context.ok,
        );
        verify(
          () => context.wrapper.deleteServiceAccount(
            organizationId: 42,
            serviceAccountId: 9,
          ),
        ).called(1);
      });

      test('quotes names a shell would split', () async {
        when(
          () => context.wrapper.getServiceAccounts(organizationId: 42),
        ).thenAnswer((_) async => [account(id: 5, name: "bob's bot")]);
        await context.runCommand(ServiceAccountsGetCommand(), [
          '--org-id',
          '42',
        ]);
        verify(
          () => context.logger.info(
            'Service accounts in "Acme Corp": \'bob\'\\\'\'s bot\' (id: 5).',
          ),
        ).called(1);
      });
    });

    test('asks for a service account and lists them', () async {
      expect(
        await context.runCommand(ServiceAccountsGetCommand(), [
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err(
          'Name the service account: shorebird service-accounts get '
          '<name or id>.',
        ),
      ).called(1);
      verify(
        () => context.logger.info(
          'Service accounts in "Acme Corp": release-bot (id: 383).',
        ),
      ).called(1);
    });

    test('names an unknown service account', () async {
      expect(
        await context.runCommand(ServiceAccountsGetCommand(), [
          'deploy-bot',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err(
          'No service account "deploy-bot" in "Acme Corp" (id: 42).',
        ),
      ).called(1);
    });

    test('says how to create one when there are none', () async {
      when(
        () => context.wrapper.getServiceAccounts(organizationId: 42),
      ).thenAnswer((_) async => []);
      await context.runCommand(ServiceAccountsGetCommand(), [
        'release-bot',
        '--org-id',
        '42',
      ]);
      verify(
        () => context.logger.info(
          '"Acme Corp" has no service accounts. Create one with shorebird '
          'service-accounts create <name>.',
        ),
      ).called(1);
    });

    test('stops when the organization cannot be picked', () async {
      expect(
        await context.runCommand(ServiceAccountsGetCommand(), [
          'release-bot',
          '--org-id',
          '7',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(
        () => context.wrapper.getServiceAccounts(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('reports a failure to list service accounts', () async {
      when(
        () => context.wrapper.getServiceAccounts(organizationId: 42),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsGetCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the service accounts of "Acme Corp".',
      );
    });
  });
}
