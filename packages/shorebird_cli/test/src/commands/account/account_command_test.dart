import 'package:shorebird_cli/src/commands/account/account.dart';
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

    test('says what a bare account shows', () {
      expect(command.description, contains('With no subcommand'));
    });
  });
}
