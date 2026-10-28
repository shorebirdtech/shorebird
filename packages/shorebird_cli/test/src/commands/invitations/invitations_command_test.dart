import 'package:shorebird_cli/src/commands/invitations/invitations.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(InvitationsCommand, () {
    late InvitationsCommand command;

    setUp(() {
      command = InvitationsCommand();
    });

    test('has the correct name', () {
      expect(command.name, equals('invitations'));
    });

    test('has list, accept and decline subcommands', () {
      expect(
        command.subcommands.keys,
        unorderedEquals(['list', 'accept', 'decline']),
      );
    });
  });
}
