import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A test-scoped temp directory created in `setUp` and removed in
/// `tearDown`. Call [setUpTempDir] from inside a `group` (or at the
/// top of a `main()`) to wire up the lifecycle.
late Directory tempDir;

/// Registers `setUp` and `tearDown` to create and remove [tempDir]
/// for each test. [prefix] is used as the temp dir name prefix to
/// help identify cleanup leftovers if anything goes wrong.
void setUpTempDir(String prefix) {
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(prefix);
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });
}

/// Creates a Dart package at [relativePath] under [root] with a pubspec.yaml
/// containing the given [name] and optional [dependencies] (path deps).
///
/// [sdkLine] controls the `environment.sdk` constraint; [flutterLine] adds
/// a Flutter dep if non-null; [useWorkspace] adds `resolution: workspace`.
void createPackage(
  Directory root,
  String relativePath,
  String name, {
  Map<String, String>? dependencies,
  String sdkLine = '  sdk: ^3.0.0',
  String? flutterLine,
  bool useWorkspace = false,
  bool addTestDir = false,
}) {
  final dir = Directory(p.join(root.path, relativePath))
    ..createSync(recursive: true);

  final buffer = StringBuffer()..writeln('name: $name');
  if (useWorkspace) buffer.writeln('resolution: workspace');
  buffer
    ..writeln('environment:')
    ..writeln(sdkLine);
  if (flutterLine != null && flutterLine != 'any') {
    // Quote the value so YAML doesn't choke on `>`/`<` etc.
    buffer.writeln('  flutter: "$flutterLine"');
  }

  if (flutterLine != null || dependencies != null) {
    final hasFlutterSdk = flutterLine == 'any';
    if (hasFlutterSdk || (dependencies != null && dependencies.isNotEmpty)) {
      buffer.writeln('dependencies:');
      if (hasFlutterSdk) {
        buffer
          ..writeln('  flutter:')
          ..writeln('    sdk: flutter');
      }
      if (dependencies != null) {
        for (final entry in dependencies.entries) {
          buffer
            ..writeln('  ${entry.key}:')
            ..writeln('    path: ${entry.value}');
        }
      }
    }
  }

  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(buffer.toString());

  if (addTestDir) {
    final testDir = Directory(p.join(dir.path, 'test'))
      ..createSync(recursive: true);
    File(
      p.join(testDir.path, 'example_test.dart'),
    ).writeAsStringSync('void main() {}');
  }
}

/// Creates a Dart workspace root pubspec at [root] listing [members].
void createWorkspaceRoot(
  Directory root, {
  required List<String> members,
  String name = '_',
}) {
  final buffer = StringBuffer()
    ..writeln('name: $name')
    ..writeln('environment:')
    ..writeln('  sdk: ^3.0.0')
    ..writeln('workspace:');
  for (final member in members) {
    buffer.writeln('  - $member');
  }
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(buffer.toString());
}

const _gitIdentity = ['-c', 'user.email=t@t', '-c', 'user.name=t'];

/// Stages all changes in [dir] and creates a commit with [message].
void commitAll(Directory dir, String message) {
  Process.runSync(
    'git',
    [..._gitIdentity, 'add', '-A'],
    workingDirectory: dir.path,
  );
  Process.runSync(
    'git',
    [..._gitIdentity, 'commit', '-qm', message],
    workingDirectory: dir.path,
  );
}

/// Initializes [dir] as a git repo with a single initial commit.
void initGitRepo(Directory dir) {
  Process.runSync('git', ['init', '-q'], workingDirectory: dir.path);
  commitAll(dir, 'init');
}
