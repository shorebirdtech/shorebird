import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(AuditLogCommand, () {
    late AuditLogCommand command;

    setUp(() {
      command = AuditLogCommand();
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

    test('is visible at the top level, and hidden under orgs', () {
      expect(command.hidden, isFalse);
      final orgsAuditLog = OrgsCommand().subcommands['audit-log'];
      expect(orgsAuditLog, isA<OrgsAuditLogCommand>());
      expect(orgsAuditLog!.hidden, isTrue);
    });

    test("doesn't name a plan", () {
      expect(command.description, isNot(contains('Enterprise')));
    });
  });
}
