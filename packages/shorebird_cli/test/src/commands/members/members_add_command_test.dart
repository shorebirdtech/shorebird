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

  group(MembersAddCommand, () {
    late MembersHarness h;
    late MembersAddCommand command;

    void invite(Role role, CreateOrganizationInvitation201Response response) {
      when(
        () => h.codePushClientWrapper.createOrganizationInvitation(
          organizationId: 42,
          email: 'dan@acme.com',
          role: role,
        ),
      ).thenAnswer((_) async => response);
    }

    setUp(() {
      h = MembersHarness();
      command = h.run(MembersAddCommand.new)..testArgResults = h.argResults;
      when(() => h.argResults.rest).thenReturn(['dan@acme.com']);
      when(() => h.argResults['role']).thenReturn('developer');
      invite(
        Role.developer,
        const CreateInvitationResponse(email: 'dan@acme.com'),
      );
    });

    test('defaults to the developer role', () {
      expect(command.argParser.options['role']!.defaultsTo, 'developer');
    });

    test('sends an invitation', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.success(
          'Invited dan@acme.com to "Acme Corp" as developer.',
        ),
      ).called(1);
    });

    test('says when the server added them at once', () async {
      when(() => h.argResults['role']).thenReturn('admin');
      invite(
        Role.admin,
        const AddedMemberResponse(email: 'dan@acme.com', role: Role.admin),
      );
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.success('Added dan@acme.com to "Acme Corp" as admin.'),
      ).called(1);
    });

    test('needs exactly one email', () async {
      when(() => h.argResults.rest).thenReturn([]);
      expect(await h.run(command.run), ExitCode.usage.code);
      when(() => h.argResults.rest).thenReturn(['a@acme.com', 'b@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'Name one email to invite: shorebird members add bob@acme.com.',
        ),
      ).called(2);
    });

    test('rejects something that is not an email', () async {
      when(() => h.argResults.rest).thenReturn(['dan']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(() => h.logger.err('"dan" is not an email address.')).called(1);
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

    test('reports a failed request', () async {
      when(
        () => h.codePushClientWrapper.createOrganizationInvitation(
          organizationId: 42,
          email: 'dan@acme.com',
          role: Role.developer,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to invite dan@acme.com to organization 42.',
      );
    });

    test('--json says whether they were invited or added', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'organization_id': 42,
        'email': 'dan@acme.com',
        'role': 'developer',
        'status': 'invited',
      });
    });
  });
}
