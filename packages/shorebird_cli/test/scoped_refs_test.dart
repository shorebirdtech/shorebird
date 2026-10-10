import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every `create()`d ref in `lib/` is read through `read()`, which throws at
/// runtime when the ref was never provided to `runScoped`. Unit tests always
/// provide their own values, so a ref missing from the real entrypoint only
/// fails in the shipped CLI.
void main() {
  test('every ref defined in lib/ is provided by the CLI entrypoint', () {
    final refPattern = RegExp(r'final (\w+Ref) = create');
    final definedRefs = <String>{
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final match in refPattern.allMatches(file.readAsStringSync()))
            match.group(1)!,
    };
    expect(definedRefs, isNotEmpty);

    // Refs are provided by bin/shorebird.dart, except the JSON-mode refs,
    // which the command runner provides once it has parsed --json.
    final providers = [
      p.join('bin', 'shorebird.dart'),
      p.join('lib', 'src', 'shorebird_cli_command_runner.dart'),
    ].map((path) => File(path).readAsStringSync()).join('\n');

    final missing =
        definedRefs
            .where((ref) => !RegExp('\\b$ref\\b[,.]').hasMatch(providers))
            .toList()
          ..sort();
    expect(missing, isEmpty, reason: 'Add these to runScoped values.');
  });
}
