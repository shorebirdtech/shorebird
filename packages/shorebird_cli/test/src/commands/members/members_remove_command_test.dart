import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';
import '../enterprises/enterprise_fixtures.dart';
import 'members_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MembersRemoveCommand, () {
    late MembersHarness h;
    late MembersRemoveCommand command;

    setUp(() {
      h = MembersHarness();
      command = h.run(MembersRemoveCommand.new)..testArgResults = h.argResults;
      when(() => h.argResults.rest).thenReturn(['bob@acme.com']);
      when(() => h.argResults['yes']).thenReturn(false);
      when(() => h.argResults['confirm-name']).thenReturn(null);
      when(
        () => h.logger.confirm(any(), hint: any(named: 'hint')),
      ).thenReturn(true);
      when(
        () => h.codePushClientWrapper.removeOrganizationUser(
          organizationId: 42,
          userId: 7,
        ),
      ).thenAnswer((_) async {});
      when(
        () => h.codePushClientWrapper.revokeOrganizationInvitation(
          organizationId: 42,
          invitationId: 'inv-1',
        ),
      ).thenAnswer((_) async {});
    });

    test('removes a member once confirmed', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.confirm(
          'Remove bob@acme.com from "Acme Corp"?',
          hint: any(named: 'hint'),
        ),
      ).called(1);
      verify(
        () => h.logger.success('Removed bob@acme.com from "Acme Corp".'),
      ).called(1);
    });

    test('removes nothing when the prompt is declined', () async {
      when(
        () => h.logger.confirm(any(), hint: any(named: 'hint')),
      ).thenReturn(false);
      await expectLater(h.run(command.run), throwsA(isA<ProcessExit>()));
      verifyNever(
        () => h.codePushClientWrapper.removeOrganizationUser(
          organizationId: any(named: 'organizationId'),
          userId: any(named: 'userId'),
        ),
      );
    });

    test('needs --yes when it cannot prompt', () async {
      when(() => h.shorebirdEnv.canAcceptUserInput).thenReturn(false);
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(
        () => h.codePushClientWrapper.removeOrganizationUser(
          organizationId: any(named: 'organizationId'),
          userId: any(named: 'userId'),
        ),
      );
    });

    test('needs --yes under --json', () async {
      when(() => h.shorebirdEnv.canAcceptUserInput).thenReturn(false);
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.usage.code);
      expect(json['error'], {
        'code': 'usage_error',
        'message': '--yes required when not running interactively',
        'hint': 'Re-run with --yes to remove bob@acme.com from "Acme Corp".',
      });
    });

    test('refuses to remove the owner', () async {
      when(() => h.argResults.rest).thenReturn(['alice@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'alice@acme.com owns "Acme Corp" and cannot be removed.',
        ),
      ).called(1);
      verifyNever(() => h.logger.confirm(any(), hint: any(named: 'hint')));
    });

    test('cancels an invitation named by its id, once confirmed', () async {
      when(() => h.argResults.rest).thenReturn(['inv-1']);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.confirm(
          'Cancel the invitation for carol@acme.com?',
          hint: any(named: 'hint'),
        ),
      ).called(1);
    });

    test(
      "says invitations weren't searched when the role can't see them",
      () async {
        when(
          () => h.codePushClientWrapper.maybeGetOrganizationInvitations(
            organizationId: 42,
          ),
        ).thenAnswer((_) async => null);
        when(() => h.argResults.rest).thenReturn(['carol@acme.com']);
        expect(await h.run(command.run), ExitCode.usage.code);
        verify(
          () =>
              h.logger.err('"carol@acme.com" is not a member of "Acme Corp".'),
        ).called(1);
      },
    );

    test('cancels a pending invitation', () async {
      when(() => h.argResults.rest).thenReturn(['carol@acme.com']);
      when(() => h.argResults['yes']).thenReturn(true);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.codePushClientWrapper.revokeOrganizationInvitation(
          organizationId: 42,
          invitationId: 'inv-1',
        ),
      ).called(1);
      verify(
        () => h.logger.success(
          'Cancelled the invitation for carol@acme.com to "Acme Corp".',
        ),
      ).called(1);
    });

    test('rejects someone who is neither member nor invited', () async {
      when(() => h.argResults.rest).thenReturn(['dan@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          '"dan@acme.com" is not a member of "Acme Corp" and has no pending '
          'invitation.',
        ),
      ).called(1);
    });

    test('needs exactly one member', () async {
      when(() => h.argResults.rest).thenReturn([]);
      expect(await h.run(command.run), ExitCode.usage.code);
    });

    test('stops when the organization cannot be picked', () async {
      when(() => h.argResults['org-id']).thenReturn('99');
      expect(await h.run(command.run), ExitCode.usage.code);
    });

    test('reports a failed fetch', () async {
      when(
        () => h.codePushClientWrapper.getOrganizationUsers(organizationId: 42),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, json: _) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
    });

    test('reports a failed removal', () async {
      when(() => h.argResults['yes']).thenReturn(true);
      when(
        () => h.codePushClientWrapper.removeOrganizationUser(
          organizationId: 42,
          userId: 7,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to remove bob@acme.com from organization 42.',
      );
    });

    test('reports a failed cancellation', () async {
      when(() => h.argResults.rest).thenReturn(['carol@acme.com']);
      when(() => h.argResults['yes']).thenReturn(true);
      when(
        () => h.codePushClientWrapper.revokeOrganizationInvitation(
          organizationId: 42,
          invitationId: 'inv-1',
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        'Failed to cancel the invitation for carol@acme.com.',
      );
    });

    test('--json says what was removed', () async {
      when(() => h.argResults['yes']).thenReturn(true);
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'organization_id': 42,
        'email': 'bob@acme.com',
        'status': 'member',
      });
    });
  });

  group('MembersRemoveCommand --enterprise', () {
    late MembersHarness h;
    late MembersRemoveCommand command;
    late Browser browser;

    setUp(() {
      h = MembersHarness();
      browser = MockBrowser();
      when(() => browser.canOpen).thenReturn(false);
      when(() => h.argResults['org-id']).thenReturn(null);
      when(() => h.argResults['enterprise']).thenReturn(true);
      when(() => h.argResults.rest).thenReturn(['bob@acme.com']);
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acme]);
      when(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).thenAnswer((_) async => [EnterpriseFixtures.member()]);
      command = h.run(MembersRemoveCommand.new)..testArgResults = h.argResults;
    });

    Future<int> run({bool json = false}) => runScoped(
      () => h.run(command.run, json: json),
      values: {browserRef.overrideWith(() => browser)},
    );

    test('sends them to the console, changing nothing', () async {
      expect(await run(), ExitCode.success.code);
      final message =
          verify(() => h.logger.info(captureAny())).captured.single as String;
      expect(
        message,
        allOf(
          contains('remove bob@acme.com from "Acme"'),
          contains('enterprise/people'),
        ),
      );
      verifyNever(() => h.logger.confirm(any(), hint: any(named: 'hint')));
    });

    test('fails naming the console page when nobody can finish it', () async {
      when(() => h.shorebirdEnv.canAcceptUserInput).thenReturn(false);
      final (:exitCode, :json) = await captureJson(() => run(json: true));
      expect(exitCode, ExitCode.unavailable.code);
      expect((json['error'] as Map)['code'], 'console_required');
    });

    test('reports someone not in the directory', () async {
      when(() => h.argResults.rest).thenReturn(['nobody@acme.com']);
      expect(await run(), ExitCode.usage.code);
      verify(
        () => h.logger.err('"nobody@acme.com" is not a member of "Acme".'),
      ).called(1);
    });

    test('rejects --org-id with --enterprise', () async {
      when(() => h.argResults['org-id']).thenReturn('42');
      expect(await run(), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          '--enterprise covers every organization in your enterprise, so '
          'it takes no --org-id.',
        ),
      ).called(1);
    });
  });
}
