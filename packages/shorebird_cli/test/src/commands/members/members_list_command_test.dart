import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../enterprises/enterprise_fixtures.dart';
import 'members_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MembersListCommand, () {
    late MembersHarness h;
    late MembersListCommand command;

    setUp(() {
      h = MembersHarness();
      command = h.run(MembersListCommand.new)..testArgResults = h.argResults;
    });

    test('prints members, then pending invitations', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(
          startsWith('1  '),
          contains('alice@acme.com'),
          endsWith(
            'owner  member',
          ),
        ),
        allOf(
          startsWith('7  '),
          contains('bob@acme.com'),
          endsWith(
            'developer  member',
          ),
        ),
        allOf(
          startsWith('inv-1  '),
          contains('carol@acme.com'),
          endsWith(
            'viewer  invited (expires 2026-11-10)',
          ),
        ),
      ]);
    });

    group("when the user's role can't see invitations", () {
      setUp(() {
        when(
          () => h.codePushClientWrapper.maybeGetOrganizationInvitations(
            organizationId: 42,
          ),
        ).thenAnswer((_) async => null);
      });

      test('lists the members and says invitations are hidden', () async {
        expect(await h.run(command.run), ExitCode.success.code);
        verify(() => h.logger.info(any())).called(2);
        verify(
          () => h.logger.warn(
            'Pending invitations are not shown: your role in this '
            "organization can't see them.",
          ),
        ).called(1);
      });

      test('--json says invitations are not shown', () async {
        final (:exitCode, :json) = await captureJson(
          () => h.run(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        final data = json['data'] as Map<String, dynamic>;
        expect(data['invitations_shown'], isFalse);
        expect(data['members'], hasLength(2));
      });
    });

    test('stops when the organization cannot be picked', () async {
      when(() => h.argResults['org-id']).thenReturn('99');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(
        () => h.codePushClientWrapper.getOrganizationUsers(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.maybeGetOrganizationInvitations(
          organizationId: 42,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the members of organization 42.',
      );
    });

    test('--json emits members and invitations with a status', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'organization_id': 42,
        'invitations_shown': true,
        'members': [
          {
            'status': 'member',
            'user_id': 1,
            'email': 'alice@acme.com',
            'name': null,
            'role': 'owner',
          },
          {
            'status': 'member',
            'user_id': 7,
            'email': 'bob@acme.com',
            'name': 'Bob',
            'role': 'developer',
          },
          {
            'status': 'invited',
            'invitation_id': 'inv-1',
            'email': 'carol@acme.com',
            'role': 'viewer',
            'invited_at': '2026-10-27T00:00:00.000Z',
            'expires_at': '2026-11-10T00:00:00.000Z',
          },
        ],
      });
    });
  });

  group('MembersListCommand --enterprise-id', () {
    late MembersHarness h;
    late MembersListCommand command;

    setUp(() {
      h = MembersHarness();
      when(() => h.argResults['org-id']).thenReturn(null);
      when(() => h.argResults['enterprise-id']).thenReturn('7');
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acme]);
      when(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).thenAnswer(
        (_) async => [
          EnterpriseFixtures.member(),
          EnterpriseFixtures.member(
            userId: 11,
            email: 'old@acme.com',
            removedAt: '2026-10-01T00:00:00.000Z',
          ),
        ],
      );
      when(
        () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
      ).thenAnswer((_) async => [EnterpriseFixtures.guest]);
      command = h.run(MembersListCommand.new)..testArgResults = h.argResults;
    });

    test('lists the directory with enterprise roles', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      final lines = verify(
        () => h.logger.info(captureAny()),
      ).captured.cast<String>();
      expect(lines, [
        allOf(
          startsWith('9  '),
          contains('bob@acme.com'),
          endsWith('member  2 organizations'),
        ),
        allOf(
          startsWith('11  '),
          endsWith('member  2 organizations  removed 2026-10-01'),
        ),
      ]);
      verifyNever(
        () => h.codePushClientWrapper.getOrganizationUsers(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('--json lists each member with their organizations', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      final data = json['data'] as Map<String, dynamic>;
      expect(data['enterprise_id'], 7);
      expect((data['members'] as List).first, {
        'user_id': 9,
        'email': 'bob@acme.com',
        'name': 'Bob',
        'role': 'member',
        'organizations': [
          {'organization_id': 42, 'role': 'developer'},
          {'organization_id': 43, 'role': 'viewer'},
        ],
        'removed_at': null,
      });
    });

    group('--guests', () {
      setUp(() => when(() => h.argResults['guests']).thenReturn(true));

      test('lists the guests', () async {
        expect(await h.run(command.run), ExitCode.success.code);
        final lines = verify(
          () => h.logger.info(captureAny()),
        ).captured.cast<String>();
        expect(lines, [
          allOf(
            startsWith('10  '),
            contains('eve@contractor.com'),
            endsWith('guest  1 organization  outside guest policy'),
          ),
        ]);
      });

      test('says when there are none', () async {
        when(
          () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
        ).thenAnswer((_) async => []);
        expect(await h.run(command.run), ExitCode.success.code);
        verify(() => h.logger.info('"Acme" has no guests.')).called(1);
      });

      test('--json lists them', () async {
        final (:exitCode, :json) = await captureJson(
          () => h.run(command.run, json: true),
        );
        expect(exitCode, ExitCode.success.code);
        expect(json['data'], {
          'enterprise_id': 7,
          'guests': [
            {
              'user_id': 10,
              'email': 'eve@contractor.com',
              'name': null,
              'organizations': [
                {'organization_id': 42, 'role': 'viewer'},
              ],
              'outside_guest_policy': true,
            },
          ],
        });
      });

      test('needs --enterprise-id', () async {
        when(() => h.argResults['enterprise-id']).thenReturn(null);
        when(() => h.argResults['org-id']).thenReturn('42');
        expect(await h.run(command.run), ExitCode.usage.code);
        verify(
          () => h.logger.err(
            "--guests lists an enterprise's guests; pass --enterprise-id too.",
          ),
        ).called(1);
      });

      test('reports a failed fetch', () async {
        when(
          () => h.codePushClientWrapper.getEnterpriseGuests(enterpriseId: 7),
        ).thenThrow(ProcessExit(ExitCode.software.code));
        final (:exitCode, :json) = await captureJson(
          () => h.run(command.run, json: true),
        );
        expect(exitCode, ExitCode.software.code);
        expect(
          (json['error'] as Map)['message'],
          'Failed to fetch the guests of enterprise 7.',
        );
      });
    });

    test('rejects --org-id with --enterprise-id', () async {
      when(() => h.argResults['org-id']).thenReturn('42');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to fetch the members of enterprise 7.',
      );
    });
  });
}
