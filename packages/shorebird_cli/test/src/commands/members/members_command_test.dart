import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
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
      expect(command.aliases, ['users', 'collaborators']);
      expect(command.subcommands['invite'], isA<MembersAddCommand>());
      expect(command.subcommands['update'], isA<MembersSetRoleCommand>());
      expect(command.subcommands['delete'], isA<MembersRemoveCommand>());
    });

    test('lists members with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });
  });

  group(TopLevelMembersCommand, () {
    test('is under orgs, and hidden at the top level for blind guesses', () {
      expect(OrgsCommand().subcommands['members'], isA<MembersCommand>());
      final topLevel = TopLevelMembersCommand();
      expect(topLevel.hidden, isTrue);
      expect(topLevel.name, 'members');
      expect(topLevel.aliases, ['collaborators']);
    });
  });

  group('parseMemberRole', () {
    test('accepts every grantable role, ignoring case and separators', () {
      expect(parseMemberRole('admin').role, Role.admin);
      expect(parseMemberRole('App-Manager').role, Role.appManager);
      expect(parseMemberRole('app_manager').role, Role.appManager);
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
        'appManager, developer, viewer.',
      );
      // No plan offers auditor to members; the server refuses it.
      expect(parseMemberRole('auditor').error, startsWith('"auditor" is not'));
      expect(parseMemberRole('boss').error, startsWith('"boss" is not'));
    });
  });
}
