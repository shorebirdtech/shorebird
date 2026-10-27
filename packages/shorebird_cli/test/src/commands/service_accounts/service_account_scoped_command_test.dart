import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
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
