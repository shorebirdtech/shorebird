import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(EnterpriseCommand, () {
    late EnterpriseCommand command;

    setUp(() => command = EnterpriseCommand());

    test('has get', () {
      expect(command.subcommands.keys, ['get']);
    });

    test('answers to the plural', () {
      expect(command.aliases, ['enterprises']);
    });

    test('shows your enterprise with no subcommand', () {
      expect(command.defaultSubcommand, 'get');
    });

    test('points at --enterprise on the existing nouns', () {
      expect(command.description, contains('--enterprise'));
    });
  });
}
