import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(EnterpriseCommand, () {
    late EnterpriseCommand command;

    setUp(() => command = EnterpriseCommand());

    test('has get and the enterprise nouns', () {
      expect(
        {for (final c in command.subcommands.values) c.name},
        {
          'get',
          'members',
          'guests',
          'orgs',
          'apps',
          'audit-log',
          'usage',
          'service-accounts',
        },
      );
    });

    test('answers to the plural', () {
      expect(command.aliases, ['enterprises']);
    });

    test('shows your enterprise with no subcommand', () {
      expect(command.defaultSubcommand, 'get');
    });

    test('shows its nouns as examples, not the hidden flag', () {
      expect(command.description, contains('shorebird enterprise members'));
      expect(command.description, isNot(contains('--enterprise')));
    });
  });
}
