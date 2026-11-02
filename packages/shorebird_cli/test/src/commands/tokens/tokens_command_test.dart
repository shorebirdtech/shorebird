import 'package:shorebird_cli/src/commands/account_list_command.dart';
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
      expect(command.aliases, containsAll(['api-keys', 'token']));
    });

    test('delete is also reachable as revoke', () {
      expect(
        command.subcommands['revoke'],
        same(command.subcommands['delete']),
      );
    });

    test('lists API keys when given no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });

    test('list lists keys, falling back to the API keys page', () {
      final list = command.subcommands['list'];
      expect(
        list,
        isA<AccountListCommand>()
            .having((c) => c.apiPath, 'apiPath', 'api/api-keys')
            .having((c) => c.consolePath, 'consolePath', 'account/api-keys'),
      );
      expect(
        (list! as AccountListCommand).describe({
          'id': '5',
          'name': 'ci',
          'created_at': '2026-10-01T00:00:00.000Z',
          'last_used_at': null,
          'expires_at': '2027-01-01T00:00:00.000Z',
        }),
        allOf(
          startsWith('5  '),
          contains('ci'),
          contains('created 2026-10-01  last used never  expires 2027-01-01'),
        ),
      );
    });

    test('create and delete open the API keys page', () {
      for (final subcommand in [
        command.subcommands['create'],
        command.subcommands['delete'],
      ]) {
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
