import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/action_versions.dart';
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

Future<int?> runUpdate(
  Directory workflowDir, {
  LatestMajorResolver? resolveLatestMajor,
}) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(
      UpdateActionsCommand(resolveLatestMajor: resolveLatestMajor),
    );
  return runner.run([
    'update_actions',
    '--workflow-dir',
    workflowDir.path,
  ]);
}

void main() {
  setUpTempDir('shorebird_ci_update_actions_');

  test('returns 1 when workflow dir does not exist', () async {
    final missing = Directory(p.join(tempDir.path, 'nope'));
    expect(await runUpdate(missing), 1);
  });

  test('returns 0 when no workflow files exist', () async {
    expect(await runUpdate(tempDir), 0);
  });

  test('leaves files without `uses:` references unchanged', () async {
    final file = File(p.join(tempDir.path, 'simple.yaml'));
    const content = '''
name: simple
on: [push]
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
''';
    file.writeAsStringSync(content);

    expect(await runUpdate(tempDir), 0);
    expect(file.readAsStringSync(), equals(content));
  });

  test('leaves SHA-pinned actions unchanged', () async {
    final file = File(p.join(tempDir.path, 'sha_pinned.yaml'));
    const content = '''
steps:
  - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
''';
    file.writeAsStringSync(content);

    expect(await runUpdate(tempDir), 0);
    expect(file.readAsStringSync(), equals(content));
  });

  test(
    'rewrites action versions when the resolver returns a new major',
    () async {
      final file = File(p.join(tempDir.path, 'has_uses.yaml'));
      const before = '''
steps:
  - uses: actions/checkout@v3
''';
      file.writeAsStringSync(before);

      Future<String?> resolver(String repo) async => 'v9';
      expect(
        await runUpdate(tempDir, resolveLatestMajor: resolver),
        0,
      );
      expect(
        file.readAsStringSync(),
        equals('''
steps:
  - uses: actions/checkout@v9
'''),
      );
    },
  );

  test('leaves files alone when the resolver returns the same major', () async {
    final file = File(p.join(tempDir.path, 'already_latest.yaml'));
    const content = '''
steps:
  - uses: actions/checkout@v4
''';
    file.writeAsStringSync(content);

    Future<String?> resolver(String repo) async => 'v4';
    expect(await runUpdate(tempDir, resolveLatestMajor: resolver), 0);
    expect(file.readAsStringSync(), equals(content));
  });

  test('skips actions when the resolver returns null', () async {
    // Covers the `latest == null` early-continue branch.
    final file = File(p.join(tempDir.path, 'unresolvable.yaml'));
    const content = '''
steps:
  - uses: actions/checkout@v3
''';
    file.writeAsStringSync(content);

    Future<String?> resolver(String repo) async => null;
    expect(await runUpdate(tempDir, resolveLatestMajor: resolver), 0);
    expect(file.readAsStringSync(), equals(content));
  });

  test('exposes a non-empty description', () {
    expect(UpdateActionsCommand().description, isNotEmpty);
  });
}
