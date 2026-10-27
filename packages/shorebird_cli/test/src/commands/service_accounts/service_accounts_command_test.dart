import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(ServiceAccountsCommand, () {
    test('has the subcommands and spellings agents guess', () {
      final command = ServiceAccountsCommand();
      expect(command.subcommands.keys, [
        'create',
        'delete',
        'get',
        'describe',
        'keys',
        'credentials',
        'list',
        'set-role',
      ]);
      expect(command.defaultSubcommand, 'list');
      expect(command.aliases, ['service-account']);
      expect(
        command.subcommands['keys']!.subcommands.keys,
        containsAll(['create', 'list', 'revoke', 'delete']),
      );
    });
  });
}
