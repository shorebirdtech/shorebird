import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'service_account_fixtures.dart';

void main() {
  useTempWorkingDirectory();

  group(ServiceAccountsGetCommand, () {
    late ServiceAccountTestContext context;

    setUp(() => context = ServiceAccountTestContext());

    test('shows the account and its keys', () async {
      expect(
        await context.runCommand(ServiceAccountsGetCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ]),
        context.ok,
      );
      expect(context.infoLines, [
        contains('release-bot[bot]'),
        'id: 383',
        'role: developer',
        'created: 2026-10-01 by admin@acme.com',
        'last signed in: 2026-10-20',
        'keys:',
        '  12  ci  created 2026-10-01  expires 2027-10-01  last used never',
      ]);
    });

    test('says when it has no keys', () async {
      when(
        () => context.wrapper.getServiceAccountKeys(
          organizationId: 42,
          serviceAccountId: 383,
        ),
      ).thenAnswer((_) async => []);
      await context.runCommand(ServiceAccountsGetCommand(), [
        'release-bot',
        '--org-id',
        '42',
      ]);
      expect(context.infoLines.last, 'keys: none');
    });

    test('is also spelled describe', () {
      expect(ServiceAccountsGetCommand().aliases, ['describe']);
    });

    test('--json emits the account with its keys', () async {
      final (:exitCode, :json) = await captureJson(
        () => context.runCommand(ServiceAccountsGetCommand(), [
          'release-bot',
          '--org-id',
          '42',
        ], json: true),
      );
      expect(exitCode, context.ok);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['name'], 'release-bot');
      expect(data['keys'], [
        {
          'id': 12,
          'name': 'ci',
          'created_at': '2026-10-01T00:00:00.000Z',
          'expires_at': '2027-10-01T00:00:00.000Z',
          'last_used_at': null,
        },
      ]);
    });
  });
}
