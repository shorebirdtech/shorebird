import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/account_list_command.dart';
import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(AccountCommand, () {
    late AccountCommand command;

    setUp(() {
      command = AccountCommand();
    });

    test('runs whoami when given no subcommand', () {
      expect(command.defaultSubcommand, equals('whoami'));
      expect(command.subcommands['whoami'], isA<WhoamiCommand>());
    });

    test('delete opens the account page', () {
      expect(
        command.subcommands['delete'],
        isA<ConsolePageCommand>().having((c) => c.path, 'path', 'account'),
      );
    });

    test('sessions lists sessions, falling back to the account page', () {
      expect(
        command.subcommands['sessions'],
        isA<AccountListCommand>()
            .having((c) => c.apiPath, 'apiPath', 'api/sessions')
            .having((c) => c.consolePath, 'consolePath', 'account'),
      );
    });

    test('sessions describes each session on one line', () {
      final sessions = command.subcommands['sessions']! as AccountListCommand;
      expect(
        sessions.describe({
          'id': '7',
          'name': 'Shorebird CLI',
          'ip_address': '203.0.113.9',
          'user_agent': 'Dart/3.9',
          'last_used_at': '2026-10-27T14:00:00.000Z',
          'is_current': true,
        }),
        allOf(
          startsWith('7  '),
          contains('Shorebird CLI'),
          contains('203.0.113.9  Dart/3.9  last used 2026-10-27  (current)'),
        ),
      );
    });

    test('says what a bare account shows', () {
      expect(command.description, contains('With no subcommand'));
    });
  });
}
