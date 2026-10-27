import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(OrgsCommand, () {
    late OrgsCommand command;

    setUp(() {
      command = OrgsCommand();
    });

    test('lists, creates, shows and renames organizations', () {
      expect(
        command.subcommands.keys,
        containsAll(['create', 'get', 'list', 'update']),
      );
    });

    test('accepts the spellings agents guess', () {
      expect(command.aliases, ['organizations', 'org', 'teams']);
    });

    test('lists organizations with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });
  });

  group(AccountOrgsCommand, () {
    test('stays under account, hidden, for existing scripts', () {
      final orgs = AccountCommand().subcommands['orgs'];
      expect(orgs, isA<AccountOrgsCommand>());
      expect(orgs!.hidden, isTrue);
    });
  });
}
