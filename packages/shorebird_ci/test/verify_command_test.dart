import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

Future<int?> runVerify(
  Directory repoRoot, {
  List<String> extra = const [],
}) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(VerifyCommand());
  return runner.run([
    'verify',
    '--repo-root',
    repoRoot.path,
    ...extra,
  ]);
}

void _writeWorkflow(Directory repoRoot, String name, String content) {
  final workflows = Directory(
    p.join(repoRoot.path, '.github', 'workflows'),
  )..createSync(recursive: true);
  File(p.join(workflows.path, name)).writeAsStringSync(content);
}

void main() {
  setUpTempDir('shorebird_ci_verify_');

  test('returns 1 when no .github/workflows directory exists', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    initGitRepo(tempDir);

    expect(await runVerify(tempDir), 1);
  });

  test('dynamic workflow → passes even with packages in repo', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/bar', 'bar');
    _writeWorkflow(tempDir, 'ci.yaml', '''
# shorebird_ci-managed: dynamic
name: CI
on: [push]
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: shorebird_ci affected_packages --sdk dart
''');
    initGitRepo(tempDir);

    expect(await runVerify(tempDir), 0);
  });

  test('mention without marker does not count as dynamic coverage', () async {
    // Regression: an earlier version substring-searched for the call,
    // so any YAML comment, run-string, or commented-out step that
    // happened to mention `shorebird_ci affected_packages` would be
    // treated as dynamic coverage. The marker comment makes intent
    // explicit.
    createPackage(tempDir, 'packages/foo', 'foo');
    _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
# Note: shorebird_ci affected_packages used to live here.
on: [push]
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - run: echo "see shorebird_ci affected_packages docs"
''');
    initGitRepo(tempDir);

    // No marker → not dynamic → falls back to static dorny check →
    // foo isn't in any filter → fail.
    expect(await runVerify(tempDir), 1);
  });

  test('static workflow with all packages covered → passes', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/bar', 'bar');
    _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - packages/foo/**
            bar:
              - packages/bar/**
''');
    initGitRepo(tempDir);

    expect(await runVerify(tempDir), 0);
  });

  test('static workflow missing a package → returns 1', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/missing_one', 'missing_one');
    _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - packages/foo/**
''');
    initGitRepo(tempDir);

    expect(await runVerify(tempDir), 1);
  });

  test('exposes a non-empty description', () {
    expect(VerifyCommand().description, isNotEmpty);
  });

  test('--ignore excludes named packages', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/e2e', 'e2e');
    _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - packages/foo/**
''');
    initGitRepo(tempDir);

    // Without --ignore, e2e is flagged as missing.
    expect(await runVerify(tempDir), 1);
    // With --ignore, e2e is skipped.
    expect(await runVerify(tempDir, extra: ['--ignore', 'e2e']), 0);
  });
}
