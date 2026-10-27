import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/commands/tokens/tokens.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(TokensCommand, () {
    late TokensCommand command;

    setUp(() => command = TokensCommand());

    test('is also reachable as api-keys', () {
      expect(command.name, 'tokens');
      expect(command.aliases, contains('api-keys'));
    });

    test('lists API keys when given no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });

    test('each subcommand opens the API keys page', () {
      expect(
        command.subcommands.keys,
        containsAll(['create', 'delete', 'list']),
      );
      for (final subcommand in command.subcommands.values) {
        expect(
          subcommand,
          isA<ConsolePageCommand>().having(
            (c) => c.path,
            'path',
            'account/api-keys',
          ),
        );
      }
    });
  });
}
