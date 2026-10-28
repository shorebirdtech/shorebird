import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(EnterprisesCommand, () {
    late EnterprisesCommand command;

    setUp(() => command = EnterprisesCommand());

    test('has list and get', () {
      expect(command.subcommands.keys, containsAll(['get', 'list']));
    });

    test('answers to the singular', () {
      expect(command.aliases, ['enterprise']);
    });

    test('lists enterprises with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });

    test('points at --enterprise-id on the existing nouns', () {
      expect(command.description, contains('--enterprise-id'));
    });
  });
}
