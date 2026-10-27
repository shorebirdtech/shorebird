import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  group(ServiceAccountsDeleteCommand, () {
    late ServiceAccountTestContext context;

    setUp(() {
      context = ServiceAccountTestContext();
      when(
        () => context.wrapper.deleteServiceAccount(
          organizationId: 42,
          serviceAccountId: 383,
        ),
      ).thenAnswer((_) async {});
    });

    test('deletes with --yes', () async {
      expect(
        await context.runCommand(ServiceAccountsDeleteCommand(), [
          'release-bot',
          '--yes',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.logger.success('Deleted service account "release-bot".'),
      ).called(1);
    });

    test('needs --yes when it cannot prompt', () async {
      expect(
        await context.runCommand(ServiceAccountsDeleteCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(
        () => context.wrapper.deleteServiceAccount(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
        ),
      );
    });

    test('deletes once the user confirms', () async {
      when(() => context.env.canAcceptUserInput).thenReturn(true);
      when(
        () => context.logger.confirm(any(), hint: any(named: 'hint')),
      ).thenReturn(true);
      expect(
        await context.runCommand(ServiceAccountsDeleteCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.logger.confirm(
          'Delete service account "release-bot"?',
          hint: any(named: 'hint'),
        ),
      ).called(1);
    });

    test(
      '--json without --yes reports one error and deletes nothing',
      () async {
        final (:exitCode, :json) = await captureJson(
          () => context.runCommand(ServiceAccountsDeleteCommand(), [
            'release-bot',
            '--org-id',
            '42',
          ], json: true),
        );
        expect(exitCode, ExitCode.usage.code);
        expect((json['error'] as Map)['message'], yesRequiredMessage);
        verifyNever(
          () => context.wrapper.deleteServiceAccount(
            organizationId: any(named: 'organizationId'),
            serviceAccountId: any(named: 'serviceAccountId'),
          ),
        );
      },
    );

    test('rejects a second service account before any request', () async {
      expect(
        await context.runCommand(ServiceAccountsDeleteCommand(), [
          'old-bot',
          'other bot',
          '--yes',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err("Too many arguments: old-bot 'other bot'."),
      ).called(1);
      verify(
        () => context.logger.info(
          'Usage: shorebird service-accounts delete <name or id>',
        ),
      ).called(1);
      verifyNever(() => context.wrapper.getOrganizationMemberships());
    });

    test('--json emits what it deleted', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsDeleteCommand(), [
          'release-bot',
          '--yes',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect(json['data'], {'id': 383, 'name': 'release-bot'});
    });
  });
}
