import 'package:args/command_runner.dart';
import 'package:shorebird_cli/src/shorebird_cli_command_runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  // Help text that names a flag the command does not have sends the reader off
  // to debug their own typo. Parsing every example keeps the examples honest
  // as flags are renamed and removed.
  group('help examples', () {
    test('every example invocation in help parses', () {
      final invalid = <String>[];
      var checked = 0;

      void walk(Command<int> command, String path) {
        for (final line in command.description.split('\n')) {
          final example = line.trim();
          if (!example.startsWith('shorebird ')) continue;
          checked++;
          try {
            ShorebirdCliCommandRunner().parse(
              _splitCommandLine(example).skip(1).toList(),
            );
          } on UsageException catch (error) {
            invalid.add(
              '$path: $example\n  ${error.message.split('\n').first}',
            );
          }
        }
        for (final sub in command.subcommands.values) {
          walk(sub, '$path ${sub.name}');
        }
      }

      for (final command in ShorebirdCliCommandRunner().commands.values) {
        walk(command, command.name);
      }

      expect(invalid, isEmpty, reason: invalid.join('\n'));
      expect(checked, greaterThan(0), reason: 'found no examples to check');
    });
  });
}

/// Splits an example on spaces, keeping a double-quoted run together so a
/// quoted value does not read as several arguments.
List<String> _splitCommandLine(String line) {
  final args = <String>[];
  final current = StringBuffer();
  var inQuotes = false;
  for (final char in line.split('')) {
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ' ' && !inQuotes) {
      if (current.isNotEmpty) {
        args.add(current.toString());
        current.clear();
      }
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) args.add(current.toString());
  return args;
}
