import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group('dartPackageInputs', () {
    late Directory root;
    setUp(() => root = tempDir());

    void pubspec(String package, String yaml) =>
        File(p.join(root.path, package, 'pubspec.yaml'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(yaml);

    test('is the package, its path closure and the workspace files', () {
      pubspec('packages/app', '''
name: app
dependencies:
  lib_a:
    path: ../lib_a
  http: ^1.0.0
  remote:
    git:
      url: https://example.com/r.git
      path: packages/remote
dev_dependencies:
  test_helpers:
    path: ../test_helpers
''');
      pubspec('packages/lib_a', '''
name: lib_a
dependencies:
  lib_b:
    path: ../lib_b
dev_dependencies:
  only_lib_a_tests:
    path: ../only_lib_a_tests
''');
      pubspec('packages/lib_b', '''
name: lib_b
dependencies:
  lib_a:
    path: ../lib_a
''');
      pubspec('packages/test_helpers', 'name: test_helpers\n');

      expect(dartPackageInputs(root.path, 'packages/app'), [
        'analysis_options.yaml',
        'packages/app',
        'packages/lib_a',
        'packages/lib_b',
        'packages/test_helpers',
        'pubspec.lock',
        'pubspec.yaml',
      ]);
    });

    test('adds what verify_cache: inputs: lists, from the package', () {
      pubspec('packages/app', '''
name: app
verify_cache:
  inputs:
    - ../../web/golden.json
    - fixtures/../../shared
''');
      expect(
        dartPackageInputs(root.path, 'packages/app'),
        containsAll(['web/golden.json', 'packages/shared']),
      );
    });

    test('a path outside the root is a FormatException', () {
      pubspec('packages/app', '''
name: app
dependencies:
  outside:
    path: ../../../elsewhere
''');
      expect(
        () => dartPackageInputs(root.path, 'packages/app'),
        throwsFormatException,
      );
    });

    test('a pubspec that is not a map is a FormatException', () {
      pubspec('packages/app', '- a list\n');
      expect(
        () => dartPackageInputs(root.path, 'packages/app'),
        throwsFormatException,
      );
    });

    test('a dependency with no pubspec ends the walk there', () {
      pubspec('packages/app', '''
name: app
dependencies:
  missing:
    path: ../missing
''');
      expect(
        dartPackageInputs(root.path, 'packages/app'),
        contains('packages/missing'),
      );
    });
  });
}
