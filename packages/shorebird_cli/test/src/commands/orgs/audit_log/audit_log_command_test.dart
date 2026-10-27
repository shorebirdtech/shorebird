import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:test/test.dart';

import '../../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(OrgsAuditLogCommand, () {
    late OrgsAuditLogCommand command;

    setUp(() {
      command = OrgsAuditLogCommand();
    });

    test('lists and exports', () {
      expect(command.subcommands.keys, containsAll(['list', 'export']));
    });

    test('shows one page with no subcommand', () {
      expect(command.defaultSubcommand, 'list');
    });

    test('accepts the spellings agents guess', () {
      expect(command.aliases, ['audit-logs', 'audit']);
    });

    test('is under orgs, and hidden at the top level', () {
      expect(
        OrgsCommand().subcommands['audit-log'],
        isA<OrgsAuditLogCommand>(),
      );
      expect(TopLevelAuditLogCommand().hidden, isTrue);
    });

    test("doesn't name a plan", () {
      expect(command.description, isNot(contains('Enterprise')));
    });
  });
}
