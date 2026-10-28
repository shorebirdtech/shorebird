import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../enterprises/enterprise_fixtures.dart';
import 'members_test_harness.dart';

void main() {
  useTempWorkingDirectory();

  group(MembersSetRoleCommand, () {
    late MembersHarness h;
    late MembersSetRoleCommand command;

    setUpAll(() {
      registerFallbackValue(Role.developer);
    });

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

    test('finds a member by user id, trimmed', () async {
      when(() => h.argResults.rest).thenReturn([' 7 ']);
      expect(await h.run(command.run), ExitCode.success.code);
    });

    test('fetches invitations only when no member matches', () async {
      await h.run(command.run);
      verifyNever(
        () => h.codePushClientWrapper.maybeGetOrganizationInvitations(
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('finds a pending invitation by its id', () async {
      when(() => h.argResults.rest).thenReturn(['inv-1']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'carol@acme.com has not accepted their invitation yet, so their '
          'role cannot be changed.',
        ),
      ).called(1);
    });

    test("refuses to change the owner's role", () async {
      when(() => h.argResults.rest).thenReturn(['alice@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'alice@acme.com owns "Acme Corp", so their role cannot be changed '
          'here.',
        ),
      ).called(1);
      verifyNever(
        () => h.codePushClientWrapper.updateOrganizationUser(
          organizationId: any(named: 'organizationId'),
          userId: any(named: 'userId'),
          role: any(named: 'role'),
        ),
      );
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

    test('succeeds without a request for the role they already have', () async {
      when(() => h.argResults['role']).thenReturn('developer');
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.info(
          'bob@acme.com is already developer in "Acme Corp"; nothing changed.',
        ),
      ).called(1);
      verifyNever(
        () => h.codePushClientWrapper.updateOrganizationUser(
          organizationId: any(named: 'organizationId'),
          userId: any(named: 'userId'),
          role: any(named: 'role'),
        ),
      );
    });

    test('--json says when nothing changed', () async {
      when(() => h.argResults['role']).thenReturn('developer');
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect((json['data'] as Map)['changed'], isFalse);
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
        'changed': true,
      });
    });
  });

  group('MembersSetRoleCommand --enterprise', () {
    late MembersHarness h;
    late MembersSetRoleCommand command;

    setUpAll(() => registerFallbackValue(EnterpriseRole.member));

    setUp(() {
      h = MembersHarness();
      when(() => h.argResults['org-id']).thenReturn(null);
      when(() => h.argResults['enterprise']).thenReturn(true);
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acmeOwner]);
      when(
        () => h.codePushClientWrapper.getEnterpriseMembers(enterpriseId: 7),
      ).thenAnswer((_) async => [EnterpriseFixtures.member()]);
      when(() => h.argResults.rest).thenReturn(['bob@acme.com']);
      when(() => h.argResults['role']).thenReturn('billing-manager');
      when(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: 7,
          userId: 9,
          role: EnterpriseRole.billingManager,
        ),
      ).thenAnswer((_) async {});
      command = h.run(MembersSetRoleCommand.new)..testArgResults = h.argResults;
    });

    test('changes the enterprise role', () async {
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: 7,
          userId: 9,
          role: EnterpriseRole.billingManager,
        ),
      ).called(1);
      verify(
        () => h.logger.success(
          'Changed bob@acme.com from member to billingManager in "Acme".',
        ),
      ).called(1);
    });

    test('changes nothing when the role is already set', () async {
      when(() => h.argResults['role']).thenReturn('member');
      when(() => h.argResults.rest).thenReturn(['9']);
      expect(await h.run(command.run), ExitCode.success.code);
      verify(
        () => h.logger.info(
          'bob@acme.com is already member in "Acme"; nothing changed.',
        ),
      ).called(1);
      verifyNever(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: any(named: 'enterpriseId'),
          userId: any(named: 'userId'),
          role: any(named: 'role'),
        ),
      );
    });

    test('--json reports the change', () async {
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.success.code);
      expect(json['data'], {
        'enterprise_id': 7,
        'user_id': 9,
        'email': 'bob@acme.com',
        'from_role': 'member',
        'to_role': 'billingManager',
        'changed': true,
      });
    });

    test('rejects an organization role', () async {
      when(() => h.argResults['role']).thenReturn('developer');
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          '"developer" is not an enterprise role. Choose one of: owner, '
          'admin, member, billingManager.',
        ),
      ).called(1);
    });

    test('needs an owner of the enterprise', () async {
      when(
        h.codePushClientWrapper.getEnterprises,
      ).thenAnswer((_) async => [EnterpriseFixtures.acme]);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err(
          'Only owners of "Acme" can change enterprise roles; you are admin.',
        ),
      ).called(1);
      verifyNever(
        () => h.codePushClientWrapper.getEnterpriseMembers(
          enterpriseId: any(named: 'enterpriseId'),
        ),
      );
    });

    test('names the directory for someone not in it', () async {
      when(() => h.argResults.rest).thenReturn(['nobody@acme.com']);
      expect(await h.run(command.run), ExitCode.usage.code);
      verify(
        () => h.logger.err('"nobody@acme.com" is not a member of "Acme".'),
      ).called(1);
      verify(
        () => h.logger.info(
          'Run `shorebird members list --enterprise` to see its members.',
        ),
      ).called(1);
    });

    test('reports a failed fetch of the directory', () async {
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

    test('reports a failed change', () async {
      when(
        () => h.codePushClientWrapper.setEnterpriseMemberRole(
          enterpriseId: 7,
          userId: 9,
          role: EnterpriseRole.billingManager,
        ),
      ).thenThrow(ProcessExit(ExitCode.software.code));
      final (:exitCode, :json) = await captureJson(
        () => h.run(command.run, json: true),
      );
      expect(exitCode, ExitCode.software.code);
      expect(
        (json['error'] as Map)['message'],
        "Failed to change bob@acme.com's enterprise role.",
      );
    });

    test('rejects --org-id with --enterprise', () async {
      when(() => h.argResults['org-id']).thenReturn('42');
      expect(await h.run(command.run), ExitCode.usage.code);
      verifyNever(h.codePushClientWrapper.getEnterprises);
    });
  });
}
