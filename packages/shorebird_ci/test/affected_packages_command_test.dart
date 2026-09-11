// cspell:words toplevel autodiscovers autodiscovery

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/affected_packages.dart';
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  setUpTempDir('shorebird_ci_affected_');

  test('rejects package paths with shell metacharacters', () async {
    // Regression: the generated workflow word-splits matrix entries
    // via `for sub in ${{ matrix.subpackages }}` — a path containing
    // shell metacharacters (e.g. an attacker-controlled subpackage
    // name) would otherwise execute as code on the runner. Reject
    // these paths in the analyzer instead so the simple shell loop is
    // safe by construction.
    createPackage(tempDir, r'packages/$(echo pwned)', 'pwned');
    initGitRepo(tempDir);

    expect(
      () => affectedPackagesMetadata(repoRoot: tempDir, all: true),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('portable POSIX paths'),
        ),
      ),
    );
  });

  test('--all lists every package with metadata', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
    initGitRepo(tempDir);

    final result = affectedPackagesMetadata(
      repoRoot: tempDir,
      all: true,
    );

    expect(result, hasLength(2));
    final names = result.map((e) => e['name']).toSet();
    expect(names, equals({'foo', 'bar'}));

    final fooEntry = result.firstWhere((e) => e['name'] == 'foo');
    expect(fooEntry['sdk'], equals('dart'));
    expect(fooEntry['path'], equals('packages/foo'));
    expect(fooEntry['has_bloc_lint'], isFalse);
    expect(fooEntry['has_integration_tests'], isFalse);
    expect(fooEntry['subpackages'], equals(''));

    final barEntry = result.firstWhere((e) => e['name'] == 'bar');
    expect(barEntry['sdk'], equals('flutter'));
  });

  test('--sdk dart filters out flutter packages', () async {
    createPackage(tempDir, 'packages/dart_pkg', 'dart_pkg');
    createPackage(
      tempDir,
      'packages/flutter_pkg',
      'flutter_pkg',
      flutterLine: 'any',
    );
    initGitRepo(tempDir);

    final result = affectedPackagesMetadata(
      repoRoot: tempDir,
      all: true,
      sdkFilter: 'dart',
    );
    expect(result, hasLength(1));
    expect(result.first['name'], equals('dart_pkg'));
  });

  test('--sdk flutter filters out dart packages', () async {
    createPackage(tempDir, 'packages/dart_pkg', 'dart_pkg');
    createPackage(
      tempDir,
      'packages/flutter_pkg',
      'flutter_pkg',
      flutterLine: 'any',
    );
    initGitRepo(tempDir);

    final result = affectedPackagesMetadata(
      repoRoot: tempDir,
      all: true,
      sdkFilter: 'flutter',
    );
    expect(result, hasLength(1));
    expect(result.first['name'], equals('flutter_pkg'));
  });

  test('empty repo returns empty list', () async {
    initGitRepo(tempDir);
    final result = affectedPackagesMetadata(
      repoRoot: tempDir,
      all: true,
    );
    expect(result, isEmpty);
  });

  test('without --all uses git diff to compute affected packages', () async {
    createPackage(tempDir, 'packages/foo', 'foo');
    createPackage(tempDir, 'packages/bar', 'bar');
    initGitRepo(tempDir);
    File(
      p.join(tempDir.path, 'packages/foo/change.txt'),
    ).writeAsStringSync('x');
    commitAll(tempDir, 'change foo');

    final result = affectedPackagesMetadata(
      repoRoot: tempDir,
      baseRef: 'HEAD~1',
      headRef: 'HEAD',
    );

    expect(result.map((e) => e['name']).toSet(), equals({'foo'}));
  });

  test('uses default base/head refs when none provided', () async {
    // Exercises the `?? 'origin/main'` and `?? 'HEAD'` defaults.
    // origin/main isn't set up in this temp repo, so the underlying
    // `git diff` will fail; we expect that failure to surface (which
    // confirms the default refs are wired in).
    createPackage(tempDir, 'packages/foo', 'foo');
    initGitRepo(tempDir);

    expect(
      () => affectedPackagesMetadata(repoRoot: tempDir),
      throwsA(isA<ProcessException>()),
    );
  });

  // Smoke test of the CLI wrapper — exercises arg parsing and the
  // empty-result path. The data-building logic is tested directly
  // above against the helper.
  test('command exits 0 on a repo with no packages', () async {
    initGitRepo(tempDir);
    final runner = CommandRunner<int>('test', 'test')
      ..addCommand(AffectedPackagesCommand());
    final code = await runner.run([
      'affected_packages',
      '--repo-root',
      tempDir.path,
      '--all',
    ]);
    expect(code, 0);
  });

  test('command emits JSON when --all finds packages', () async {
    // Exercises the `stdout.writeln(jsonEncode(result))` branch of run().
    createPackage(tempDir, 'packages/foo', 'foo');
    initGitRepo(tempDir);

    final runner = CommandRunner<int>('test', 'test')
      ..addCommand(AffectedPackagesCommand());
    final code = await runner.run([
      'affected_packages',
      '--repo-root',
      tempDir.path,
      '--all',
    ]);
    expect(code, 0);
  });

  test('command exposes a non-empty description', () {
    expect(AffectedPackagesCommand().description, isNotEmpty);
  });

  test(
    'command exits 1 (not stack-traces) when run outside a git repo',
    () async {
      // tempDir is not a git repo here. Underlying helper throws
      // ProcessException; the command should catch it and surface a
      // friendly message instead of a Dart stack trace.
      createPackage(tempDir, 'packages/foo', 'foo');

      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(AffectedPackagesCommand());
      final code = await runner.run([
        'affected_packages',
        '--repo-root',
        tempDir.path,
      ]);
      expect(code, 1);
    },
  );

  test('command exits 1 when base ref is missing', () async {
    // No origin/main in the temp git repo → git diff fails with
    // "Could not access 'origin/main'". The command should report a
    // friendly error and exit 1, not throw.
    createPackage(tempDir, 'packages/foo', 'foo');
    initGitRepo(tempDir);

    final runner = CommandRunner<int>('test', 'test')
      ..addCommand(AffectedPackagesCommand());
    final code = await runner.run([
      'affected_packages',
      '--repo-root',
      tempDir.path,
    ]);
    expect(code, 1);
  });

  // The two tests below exercise the --repo-root autodiscovery path
  // (`git rev-parse --show-toplevel`) by setting Directory.current.
  // Save+restore in try/finally so subsequent tests in this file see
  // the original cwd. Test isolation across files is fine because each
  // test file runs in its own isolate w/ isolate-local cwd.
  test('repoRoot autodiscovers via git rev-parse when not passed', () async {
    initGitRepo(tempDir);
    createPackage(tempDir, 'packages/foo', 'foo');

    final original = Directory.current;
    Directory.current = tempDir;
    try {
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(AffectedPackagesCommand());
      final code = await runner.run(['affected_packages', '--all']);
      expect(code, 0);
    } finally {
      Directory.current = original;
    }
  });

  test('repoRoot falls back to "." when not inside a git repo', () async {
    // tempDir is intentionally NOT a git repo. The autodiscovery
    // `git rev-parse` will exit non-zero → mixin returns '.', which
    // resolves to tempDir (our cwd) — confirmed by the friendly-error
    // exit 1 from running git diff in a non-git tree.
    createPackage(tempDir, 'packages/foo', 'foo');

    final original = Directory.current;
    Directory.current = tempDir;
    try {
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(AffectedPackagesCommand());
      final code = await runner.run(['affected_packages']);
      expect(code, 1);
    } finally {
      Directory.current = original;
    }
  });
}
