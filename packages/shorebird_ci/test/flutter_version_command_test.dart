import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

Future<int?> runFlutterVersion(Directory pkgDir) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(FlutterVersionCommand());
  return runner.run([
    'flutter_version',
    '--pubspec',
    pkgDir.path,
  ]);
}

void main() {
  setUpTempDir('shorebird_ci_flutter_version_command_');

  test('exits 0 when an exact version is pinned', () async {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
environment:
  sdk: ^3.0.0
  flutter: 3.22.1
''');
    expect(await runFlutterVersion(tempDir), 0);
  });

  test('exits 0 when no version is pinned (falls back to stable)', () async {
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
environment:
  sdk: ^3.0.0
''');
    expect(await runFlutterVersion(tempDir), 0);
  });

  test('exposes a non-empty description', () {
    expect(FlutterVersionCommand().description, isNotEmpty);
  });
}
