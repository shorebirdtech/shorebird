import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:test/test.dart';

import '../../helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(AppsCommand, () {
    late AppsCommand command;

    setUp(() {
      command = AppsCommand();
    });

    test('offers example invocations', () {
      expect(command.description, contains('Examples:'));
    });

    // The runner lists a command by description.split('\n').first, so a
    // multi-line description must keep everything but its summary below the
    // first newline or it bloats the parent command's listing.
    test('keeps its summary to the first line', () {
      expect(
        command.description.split('\n').first,
        equals('Manage Shorebird apps.'),
      );
    });
  });
}
