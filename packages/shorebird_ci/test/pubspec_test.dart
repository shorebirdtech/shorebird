import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/pubspec.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  setUpTempDir('shorebird_ci_pubspec_');

  test('returns null when pubspec.yaml is missing', () {
    expect(readPubspec(tempDir.path), isNull);
  });

  test('returns null for malformed YAML', () {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync(
      // Mismatched bracket / unclosed structure that loadYaml rejects.
      'name: foo\nbroken: [',
    );
    expect(readPubspec(tempDir.path), isNull);
  });

  test('returns null when the top-level value is not a map', () {
    File(
      p.join(tempDir.path, 'pubspec.yaml'),
    ).writeAsStringSync('- list\n- yaml');
    expect(readPubspec(tempDir.path), isNull);
  });

  test('parses a valid pubspec', () {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: foo
environment:
  sdk: ^3.0.0
''');
    final pubspec = readPubspec(tempDir.path);
    expect(pubspec, isNotNull);
    expect(pubspec!['name'], equals('foo'));
  });
}
