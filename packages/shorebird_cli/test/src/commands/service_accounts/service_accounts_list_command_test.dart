import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
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
          'orgs service-accounts create <name>.';
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
}
