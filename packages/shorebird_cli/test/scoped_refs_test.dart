import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every scoped dependency the CLI declares must be provided when it runs.
///
/// A `read` of a ref no enclosing `runScoped` provides throws a `StateError`.
/// Command tests provide each ref themselves, so they pass whether or not the
/// real entrypoint does, and a forgotten ref only shows up when a user runs
/// the command (`shorebird login` in 1.6.126 crashed this way on `browserRef`).
void main() {
  test('every ref declared in lib/ is provided by the CLI', () {
    final declared = <String>{};
    final declaration = RegExp(r'^final (\w+Ref) = create\b', multiLine: true);
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || p.extension(file.path) != '.dart') continue;
      declared.addAll(
        declaration
            .allMatches(file.readAsStringSync())
            .map((match) => match.group(1)!),
      );
    }

    // The entrypoint provides most refs; the command runner provides the ones
    // that depend on parsed arguments (e.g. `--json`).
    final provided = <String>{
      for (final path in [
        'bin/shorebird.dart',
        'lib/src/shorebird_cli_command_runner.dart',
      ])
        ...RegExp(
          r'^\s*(\w+Ref)\b(?:\.overrideWith\b.*)?,?$',
          multiLine: true,
        ).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)!),
    };

    expect(declared, isNotEmpty);
    expect(declared.difference(provided), isEmpty);
  });
}
