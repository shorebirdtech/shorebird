import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/workspace.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  setUpTempDir('shorebird_ci_workspace_');

  void writePubspec(String relativePath, String content) {
    final dir = Directory(p.join(tempDir.path, relativePath))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(content);
  }

  group('isDartWorkspace', () {
    test('true when workspace: list is non-empty', () {
      writePubspec('.', '''
name: _
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
      expect(isDartWorkspace(tempDir.path), isTrue);
    });

    test('false when no pubspec.yaml exists', () {
      expect(isDartWorkspace(tempDir.path), isFalse);
    });

    test('false when workspace key is missing', () {
      writePubspec('.', '''
name: foo
environment:
  sdk: ^3.0.0
''');
      expect(isDartWorkspace(tempDir.path), isFalse);
    });

    test('false when workspace: list is empty', () {
      writePubspec('.', '''
name: _
environment:
  sdk: ^3.0.0
workspace: []
''');
      expect(isDartWorkspace(tempDir.path), isFalse);
    });
  });

  group('isWorkspaceStubRoot', () {
    test('true for nameless workspace', () {
      writePubspec('.', '''
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
      expect(isWorkspaceStubRoot(tempDir.path), isTrue);
    });

    test('true for underscore-prefixed name', () {
      writePubspec('.', '''
name: _
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
      expect(isWorkspaceStubRoot(tempDir.path), isTrue);
    });

    test('false for normal-named workspace', () {
      writePubspec('.', '''
name: my_workspace
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
      expect(isWorkspaceStubRoot(tempDir.path), isFalse);
    });

    test('false for non-workspace package', () {
      writePubspec('.', '''
name: foo
environment:
  sdk: ^3.0.0
''');
      expect(isWorkspaceStubRoot(tempDir.path), isFalse);
    });
  });

  group('usesWorkspaceResolution', () {
    test('true when resolution: workspace is set', () {
      writePubspec('.', '''
name: foo
resolution: workspace
environment:
  sdk: ^3.0.0
''');
      expect(usesWorkspaceResolution(tempDir.path), isTrue);
    });

    test('false when resolution key is missing', () {
      writePubspec('.', '''
name: foo
environment:
  sdk: ^3.0.0
''');
      expect(usesWorkspaceResolution(tempDir.path), isFalse);
    });

    test('false when no pubspec exists', () {
      expect(usesWorkspaceResolution(tempDir.path), isFalse);
    });
  });

  group('findWorkspaceRoot', () {
    test('walks up to find a workspace root', () {
      writePubspec('.', '''
name: _
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
      writePubspec('packages/foo', '''
name: foo
resolution: workspace
environment:
  sdk: ^3.0.0
''');

      final memberPath = p.join(tempDir.path, 'packages', 'foo');
      final root = findWorkspaceRoot(memberPath);
      expect(root, isNotNull);
      expect(p.equals(root!.path, tempDir.path), isTrue);
    });

    test('returns the directory itself if it is the workspace root', () {
      writePubspec('.', '''
name: _
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');

      final root = findWorkspaceRoot(tempDir.path);
      expect(root, isNotNull);
      expect(p.equals(root!.path, tempDir.path), isTrue);
    });

    test('returns null when no workspace root exists above', () {
      writePubspec('packages/foo', '''
name: foo
environment:
  sdk: ^3.0.0
''');
      final memberPath = p.join(tempDir.path, 'packages', 'foo');
      // No workspace root anywhere up the tree.
      expect(findWorkspaceRoot(memberPath), isNull);
    });
  });
}
