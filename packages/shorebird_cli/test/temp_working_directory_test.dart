import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/helpers.dart';

/// Tests run from the package directory, so a made-up relative path names a
/// real place in the developer's checkout, and code under test deleting a
/// parent of `File('')` deletes the checkout. [useTempWorkingDirectory]
/// resolves such paths into a temporary directory, but only in files that
/// call it.
void main() {
  useTempWorkingDirectory();

  test('every test file calls useTempWorkingDirectory first', () {
    final firstStatement = RegExp(
      r'^void main\(\) \{\n  useTempWorkingDirectory\(\);$',
      multiLine: true,
    );
    final missing = [
      for (final file in Directory(packagePath('test')).listSync(
        recursive: true,
      ))
        if (file is File &&
            file.path.endsWith('_test.dart') &&
            !firstStatement.hasMatch(file.readAsStringSync()))
          p.relative(file.path, from: packagePath('')),
    ];
    expect(missing, isEmpty);
  });

  test('relative paths resolve into the system temp directory', () {
    final systemTemp = Directory.systemTemp.path;
    expect(p.isWithin(systemTemp, Directory.current.path), isTrue);
    expect(p.isWithin(systemTemp, File('').parent.path), isTrue);
    expect(p.isWithin(systemTemp, File('a/b').path), isTrue);
    expect(() => Directory.current = systemTemp, throwsUnsupportedError);
  });
}
