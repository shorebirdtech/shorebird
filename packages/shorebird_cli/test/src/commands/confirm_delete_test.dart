import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:test/test.dart';

import '../helpers.dart';

class _TestCommand extends ShorebirdCommand with ConfirmDelete {
  _TestCommand() {
    addConfirmDeleteOptions();
  }

  @override
  String get name => 'test';

  @override
  String get description => 'A command for testing ConfirmDelete.';
}

void main() {
  useTempWorkingDirectory();
  group(ConfirmDelete, () {
    late _TestCommand command;

    setUp(() => command = _TestCommand());

    test('adds -y, --yes', () {
      final option = command.argParser.options[yesArgName]!;
      expect(option.abbr, 'y');
      expect(option.isFlag, isTrue);
      expect(option.negatable, isFalse);
      expect(option.help, 'Skip the confirmation prompt.');
      expect(command.argParser.parse(['-y'])[yesArgName], isTrue);
    });

    test('keeps --confirm-name as a hidden option', () {
      final option = command.argParser.options[confirmNameArgName]!;
      expect(option.hide, isTrue);
      expect(
        command.argParser.parse(['--confirm-name', 'x'])[confirmNameArgName],
        'x',
      );
    });
  });
}
