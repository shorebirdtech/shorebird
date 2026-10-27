import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
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
          startsWith('-  '),
          contains('carol@acme.com'),
          endsWith(
            'viewer  invited (expires 2026-11-10)',
          ),
        ),
      ]);
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
        () => h.codePushClientWrapper.getOrganizationInvitations(
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
}
