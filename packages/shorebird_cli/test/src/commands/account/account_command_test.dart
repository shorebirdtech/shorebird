import 'package:shorebird_cli/src/commands/account/account.dart';
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

    test('sessions and delete open the account page', () {
      for (final name in ['sessions', 'delete']) {
        expect(
          command.subcommands[name],
          isA<ConsolePageCommand>().having((c) => c.path, 'path', 'account'),
        );
      }
    });

    test('says what a bare account shows', () {
      expect(command.description, contains('With no subcommand'));
    });
  });
}
