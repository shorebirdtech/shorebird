import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/shorebird_ci.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  setUpTempDir('shorebird_ci_flutter_version_');

  void writePubspec(String content) {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync(content);
  }

  group('resolveFlutterVersion', () {
    test('returns exact version from environment.flutter', () {
      writePubspec('''
name: test
environment:
  sdk: ^3.0.0
  flutter: 3.22.1
''');

      expect(
        resolveFlutterVersion(packagePath: tempDir.path),
        equals('3.22.1'),
      );
    });

    test('returns null for version constraints', () {
      writePubspec('''
name: test
environment:
  sdk: ^3.0.0
  flutter: ">=3.19.0 <4.0.0"
''');

      expect(resolveFlutterVersion(packagePath: tempDir.path), isNull);
    });

    test('returns null when environment.flutter is absent', () {
      writePubspec('''
name: test
environment:
  sdk: ^3.0.0
''');

      expect(resolveFlutterVersion(packagePath: tempDir.path), isNull);
    });

    test('returns null when pubspec.yaml is missing', () {
      expect(resolveFlutterVersion(packagePath: tempDir.path), isNull);
    });

    test('returns null when pubspec.yaml is not a map', () {
      writePubspec('- just a list');
      expect(resolveFlutterVersion(packagePath: tempDir.path), isNull);
    });
  });

  group('resolveFlutterVersionOrStable', () {
    test('returns the exact version when pinned', () {
      writePubspec('''
name: test
environment:
  sdk: ^3.0.0
  flutter: 3.22.1
''');
      expect(
        resolveFlutterVersionOrStable(packagePath: tempDir.path),
        equals('3.22.1'),
      );
    });

    test('returns "stable" when nothing pinned', () {
      writePubspec('''
name: test
environment:
  sdk: ^3.0.0
''');
      expect(
        resolveFlutterVersionOrStable(packagePath: tempDir.path),
        equals('stable'),
      );
    });
  });
}
