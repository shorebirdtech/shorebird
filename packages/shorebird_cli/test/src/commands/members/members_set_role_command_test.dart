import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import 'members_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MembersSetRoleCommand, () {
    late MembersHarness h;
    late MembersSetRoleCommand command;

    setUp(() {
      h = MembersHarness();
      command = h.run(MembersSetRoleCommand.new)..testArgResults = h.argResults;
      when(() => h.argResults.rest).thenReturn(['bob@acme.com']);
      when(() => h.argResults['role']).thenReturn('admin');
      when(
        () => h.codePushClientWrapper.updateOrganizationUser(
          organizationId: 42,
          userId: 7,
          role: Role.admin,
        ),
      ).thenAnswer((_) async {});
    });

    test('changes the role of a member named by email', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.success(
          'Changed bob@acme.com from developer to admin in "Acme Corp".',
        ),
      ).called(1);
    });

    test('finds a member by user id', () async {
      when(() => h.argResults.rest).thenReturn(['7']);
      expect(await h.run(command.run), ExitCode.success.code);
    });

    test('says how to change a pending invitation', () async {
      when(() => h.argResults.rest).thenReturn(['carol@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'carol@acme.com has not accepted their invitation yet, so their '
          'role cannot be changed.',
        ),
      ).called(1);
      verify(
        () => h.logger.info(
          'Cancel it and invite them again: shorebird members remove '
          'carol@acme.com --org-id 42, then shorebird members add '
          'carol@acme.com --role admin --org-id 42.',
        ),
      ).called(1);
    });

    test('rejects someone who is not a member', () async {
      when(() => h.argResults.rest).thenReturn(['dan@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err('"dan@acme.com" is not a member of "Acme Corp".'),
      ).called(1);
    });

    test('rejects the role they already have', () async {
      when(() => h.argResults['role']).thenReturn('developer');
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err('bob@acme.com is already developer in "Acme Corp".'),
      ).called(1);
    });

    test('needs exactly one member', () async {
      when(() => h.argResults.rest).thenReturn([]);
      expect(await h.run(command.run), ExitCode.usage.code);
    });

    test('rejects the owner role before any request', () async {
      when(() => h.argResults['role']).thenReturn('owner');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(() => h.codePushClientWrapper.getOrganizationMemberships());
    });

    test('stops when the organization cannot be picked', () async {
      when(() => h.argResults['org-id']).thenReturn('99');
      expect(await h.run(command.run), ExitCode.usage.code);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getOrganizationUsers(organizationId: 42),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
    });

    test('reports a failed update', () async {
      when(
        () => h.codePushClientWrapper.updateOrganizationUser(
          organizationId: 42,
          userId: 7,
          role: Role.admin,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        "Failed to change bob@acme.com's role.",
      );
    });

    test('--json emits the old and new roles', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'organization_id': 42,
        'user_id': 7,
        'email': 'bob@acme.com',
        'from_role': 'developer',
        'to_role': 'admin',
      });
    });
  });
}
