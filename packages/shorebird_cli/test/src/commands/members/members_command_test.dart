import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import '../../helpers.dart';
import '../../mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(MembersCommand, () {
    final command = MembersCommand();

    test('lists, adds, changes and removes members', () {
      expect(
        command.subcommands.keys,
        containsAll(['add', 'list', 'remove', 'set-role']),
      );
    });

    test('accepts the spellings agents guess', () {
      expect(command.aliases, containsAll(['collaborators', 'member']));
      expect(command.subcommands['invite'], isA<MembersAddCommand>());
      expect(command.subcommands['update'], isA<MembersSetRoleCommand>());
      expect(command.subcommands['delete'], isA<MembersRemoveCommand>());
    });

    test('lists members with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });
  });

  group('parseMemberRole', () {
    test('accepts every grantable role, ignoring case and separators', () {
      expect(parseMemberRole('admin').role, Role.admin);
      expect(parseMemberRole('App-Manager').role, Role.appManager);
      expect(parseMemberRole('app_manager').role, Role.appManager);
      expect(parseMemberRole('auditor').role, Role.auditor);
    });

    test('sends ownership to the console', () {
      final shorebirdEnv = MockShorebirdEnv();
      when(() => shorebirdEnv.hostedEnvironment).thenReturn(null);
      expect(
        runScoped(
          () => parseMemberRole('owner').error,
          values: {shorebirdEnvRef.overrideWith(() => shorebirdEnv)},
        ),
        'Ownership is transferred in the console, not the CLI: '
        'https://console.shorebird.dev',
      );
    });

    test('lists the choices for anything else', () {
      expect(
        parseMemberRole('none').error,
        '"none" is not a role you can grant. Choose one of: admin, '
        'appManager, developer, viewer, auditor.',
      );
      expect(parseMemberRole('boss').error, startsWith('"boss" is not'));
    });
  });

  group('findMemberTarget', () {
    const member = OrganizationUser(
      user: PublicUser(id: 7, email: 'Bob@acme.com'),
      role: Role.developer,
    );
    final invite = InvitationSummary(
      id: 'inv-1',
      email: 'carol@acme.com',
      role: Role.viewer,
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2026, 2),
    );

    MemberTarget find(String arg) =>
        findMemberTarget(arg, members: [member], invitations: [invite]);

    test('finds a member by id or email, ignoring case', () {
      expect(find('7').member, member);
      expect(find('bob@ACME.com').member, member);
    });

    test('finds a pending invitation by email', () {
      expect(find('Carol@acme.com').invite, invite);
    });

    test('finds nothing for anyone else', () {
      final target = find('dan@acme.com');
      expect(target.member, isNull);
      expect(target.invite, isNull);
    });
  });
}
