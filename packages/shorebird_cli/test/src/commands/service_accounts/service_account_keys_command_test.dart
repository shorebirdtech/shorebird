import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  late ServiceAccountTestContext context;

  setUp(() => context = ServiceAccountTestContext());

  group(ServiceAccountKeysListCommand, () {
    test('prints one line per key', () async {
      expect(
        await context.runCommand(ServiceAccountKeysListCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      expect(context.infoLines, [
        '12  ci  created 2026-10-01  expires 2027-10-01  last used never',
      ]);
    });

    test('says when there are none', () async {
      when(
        () => context.wrapper.getServiceAccountKeys(
          organizationId: 42,
          serviceAccountId: 383,
        ),
      ).thenAnswer((_) async => []);
      await context.runCommand(ServiceAccountKeysListCommand(), [
        'release-bot',
        '--org-id',
        '42',
      ]);
      expect(context.infoLines, ['"release-bot" has no keys.']);
    });

    test('--json emits the keys', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountKeysListCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect((json['data'] as Map)['keys'], hasLength(1));
    });
  });

  group(ServiceAccountKeysRevokeCommand, () {
    setUp(() {
      when(
        () => context.wrapper.revokeServiceAccountKey(
          organizationId: 42,
          serviceAccountId: 383,
          keyId: 12,
        ),
      ).thenAnswer((_) async {});
    });

    test('revokes the key with --yes', () async {
      expect(
        await context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '12',
          '--yes',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.logger.success('Revoked key 12 ("ci") of "release-bot".'),
      ).called(1);
    });

    test('asks for the key id and lists the keys', () async {
      expect(
        await context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err(
          'Name the key to revoke: shorebird service-accounts keys revoke '
          'release-bot <key id>.',
        ),
      ).called(1);
      verify(
        () => context.logger.info('Keys of "release-bot": 12 ("ci").'),
      ).called(1);
    });

    test('names an unknown key', () async {
      expect(
        await context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '13',
          '--yes',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err('"release-bot" has no key 13.'),
      ).called(1);
    });

    test('needs --yes when it cannot prompt', () async {
      expect(
        await context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '12',
          '--org-id',
          '42',
        ]),
        ExitCode.usage.code,
      );
      verifyNever(
        () => context.wrapper.revokeServiceAccountKey(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
          keyId: any(named: 'keyId'),
        ),
      );
    });

    test('revokes nothing when the user declines', () async {
      when(() => context.env.canAcceptUserInput).thenReturn(true);
      when(
        () => context.logger.confirm(any(), hint: any(named: 'hint')),
      ).thenReturn(false);
      await expectLater(
        context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '12',
          '--org-id',
          '42',
        ]),
        throwsA(isA<PromptDeclinedExit>()),
      );
      verifyNever(
        () => context.wrapper.revokeServiceAccountKey(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
          keyId: any(named: 'keyId'),
        ),
      );
    });

    test(
      '--json without --yes reports one error and revokes nothing',
      () async {
        final (:exitCode, :json) = await captureJson(
          () => context.runCommand(ServiceAccountKeysRevokeCommand(), [
            'release-bot',
            '12',
            '--org-id',
            '42',
          ], json: true),
        );
        expect(exitCode, ExitCode.usage.code);
        expect((json['error'] as Map)['message'], yesRequiredMessage);
        verifyNever(
          () => context.wrapper.revokeServiceAccountKey(
            organizationId: any(named: 'organizationId'),
            serviceAccountId: any(named: 'serviceAccountId'),
            keyId: any(named: 'keyId'),
          ),
        );
      },
    );

    test('rejects a third argument before any request', () async {
      expect(
        await context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '12',
          '13',
          '--yes',
        ]),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err('Too many arguments: release-bot 12 13.'),
      ).called(1);
      verifyNever(() => context.wrapper.getOrganizationMemberships());
    });

    test('does not take --confirm-name', () {
      expect(
        ServiceAccountKeysRevokeCommand().argParser.options,
        isNot(contains('confirm-name')),
      );
    });

    test('--json emits what it revoked', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountKeysRevokeCommand(), [
          'release-bot',
          '12',
          '--yes',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect(json['data'], {'service_account_id': 383, 'key_id': 12});
    });
  });

  group(ServiceAccountKeysCreateCommand, () {
    test('without a terminal, fails with the console page', () async {
      const consoleUrl =
          'https://console.shorebird.dev/orgs/42/settings/service-accounts/383';
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountKeysCreateCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, ExitCode.unavailable.code);
      expect(json['error'], {
        'code': 'console_required',
        'message':
            'The Shorebird CLI does not make keys for service account '
            '"release-bot"; you do it in the Shorebird console.',
        'hint':
            'Open $consoleUrl in a browser to make keys for service account '
            '"release-bot".',
      });
      verifyNever(
        () => context.wrapper.getServiceAccountKeys(
          organizationId: any(named: 'organizationId'),
          serviceAccountId: any(named: 'serviceAccountId'),
        ),
      );
    });
  });
}
