import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
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
        'trust',
        'trust-rules',
        'oidc',
      ]);
      expect(command.defaultSubcommand, 'list');
      expect(command.aliases, ['service-account']);
      expect(
        command.subcommands['keys']!.subcommands.keys,
        containsAll(['create', 'list', 'revoke', 'delete']),
      );
      expect(
        command.subcommands['trust']!.subcommands.keys,
        containsAll(['add', 'create', 'list', 'remove', 'delete']),
      );
    });
  });

  test('is visible at the top level', () {
    expect(ServiceAccountsCommand().hidden, isFalse);
  });

  test('is also under orgs, hidden', () {
    final command = OrgsCommand().subcommands['service-accounts'];
    expect(command, isA<OrgsServiceAccountsCommand>());
    expect(command!.hidden, isTrue);
    expect(command.subcommands.keys, contains('keys'));
  });
}
