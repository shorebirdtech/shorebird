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

  group(ServiceAccountsCreateCommand, () {
    late ServiceAccountTestContext context;

    setUp(() {
      context = ServiceAccountTestContext();
      when(
        () => context.wrapper.createServiceAccount(
          organizationId: 42,
          name: 'release-bot',
          role: any(named: 'role'),
        ),
      ).thenAnswer((_) async => releaseBot);
    });

    test('creates the account and links to where keys are made', () async {
      expect(
        await context.runCommand(ServiceAccountsCreateCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      verify(
        () => context.wrapper.createServiceAccount(
          organizationId: 42,
          name: 'release-bot',
        ),
      ).called(1);
      verify(
        () => context.logger.success(
          'Created service account "release-bot" (id: 383) with role '
          'developer.',
        ),
      ).called(1);
      verify(
        () => context.logger.info(
          'Give it a key in the console: '
          'https://console.shorebird.dev/orgs/42/settings/service-accounts/383',
        ),
      ).called(1);
    });

    test('sends --role', () async {
      await context.runCommand(ServiceAccountsCreateCommand(), [
        'release-bot',
        '--role',
        'appManager',
        '--org-id',
        '42',
      ]);
      verify(
        () => context.wrapper.createServiceAccount(
          organizationId: 42,
          name: 'release-bot',
          role: ServiceAccountRole.appManager,
        ),
      ).called(1);
    });

    test('rejects no name or several', () async {
      for (final args in [
        <String>[],
        ['release', 'bot'],
      ]) {
        expect(
          await context.runCommand(ServiceAccountsCreateCommand(), args),
          ExitCode.usage.code,
        );
      }
      verify(
        () => context.logger.err(
          'Name the service account once: shorebird orgs service-accounts '
          'create release-bot.',
        ),
      ).called(2);
    });

    test('trims the name', () async {
      await context.runCommand(ServiceAccountsCreateCommand(), [
        ' release-bot ',
        '--org-id',
        '42',
      ]);
      verify(
        () => context.wrapper.createServiceAccount(
          organizationId: 42,
          name: 'release-bot',
        ),
      ).called(1);
    });

    test('rejects a blank name', () async {
      expect(
        await context.runCommand(ServiceAccountsCreateCommand(), [' ']),
        ExitCode.usage.code,
      );
      verify(
        () => context.logger.err('Service account name must not be blank.'),
      ).called(1);
    });

    test('reports a failed request', () async {
      when(
        () => context.wrapper.createServiceAccount(
          organizationId: 42,
          name: 'release-bot',
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsCreateCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to create service account "release-bot".',
      );
    });

    test('--json emits the new account', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsCreateCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      expect((json['data'] as Map)['id'], 383);
    });
  });
}
