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

  test(
    'colliding package names match by slug, not by name',
    () async {
      // Two packages share `name: harness` at different parent dirs.
      // `generate` emits the dorny filter keys as `alpha_harness` and
      // `beta_harness`. Verify must compute the same slugs to
      // recognize coverage; looking up by plain `pkg.name`
      // ("harness") would miss both.
      createPackage(tempDir, 'apps/alpha/harness', 'harness');
      createPackage(tempDir, 'apps/beta/harness', 'harness');
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
            alpha_harness:
              - apps/alpha/harness/**
            beta_harness:
              - apps/beta/harness/**
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    },
  );

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

  group('required job consistency', () {
    test('workflow without a required job → no extra check', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    });

    test('required.needs covers every other job → passes', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs:
      - changes
      - foo
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    });

    test('required.needs missing a job → returns 1', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs:
      - changes
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('required.needs as scalar string → handled', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs: changes
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      // `needs: changes` is the YAML scalar form. `foo` is missing.
      expect(await runVerify(tempDir), 1);
    });

    test('required job w/ no needs key → returns 1', () async {
      // Extreme drift: aggregator job declared but `needs:` missing
      // entirely. Every other job becomes "missing" by definition.
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('required.needs references a non-existent job → returns 1', () async {
      // Typo case: `needs:` lists a job that doesn't exist in the file.
      // GHA itself catches this at runtime, but verify catches it earlier.
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs:
      - changes
      - foo
      - foo_typo
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('required job check fires alongside dynamic coverage', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      // Dynamic-coverage workflow (so the package check is satisfied)
      // that also has a malformed required job missing the cspell entry.
      _writeWorkflow(tempDir, 'ci.yaml', '''
# shorebird_ci-managed: dynamic
name: CI
on: [push]
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - run: shorebird_ci affected_packages
  cspell:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs:
      - setup
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      // Dynamic coverage would pass on its own, but required.needs is
      // missing cspell, so verify still fails.
      expect(await runVerify(tempDir), 1);
    });

    test('drift fires alongside missing-package coverage', () async {
      // Static-style workflow w/ a package missing from filters AND a
      // required.needs that's missing a job. Exercises the
      // requiredJobErrors branch on the missing-packages path, so the
      // user sees both failures in one run.
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
    needs:
      - changes
    runs-on: ubuntu-latest
    steps:
      - run: echo
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('invalid workflow yaml is skipped, not crashing', () async {
      // verify is not a YAML linter. A file we can't parse should
      // silently fall out of the required-job check rather than
      // throwing.
      createPackage(tempDir, 'packages/foo', 'foo');
      _writeWorkflow(tempDir, 'bad.yaml', '''
name: CI
on: [push]
jobs:
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: |
        this: is: not: valid: yaml: [
''');
      _writeWorkflow(tempDir, 'ci.yaml', '''
# shorebird_ci-managed: dynamic
name: CI
on: [push]
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - run: shorebird_ci affected_packages
''');
      initGitRepo(tempDir);

      // Dynamic coverage covers the package; the bad file just gets
      // skipped during the required-job scan. Verify returns 0.
      expect(await runVerify(tempDir), 0);
    });

    test('malformed `required:` (no map body) → returns 1', () async {
      // `required:` exists as a key but has no job-map body. GHA
      // wouldn't run it, so verify can't reason about its `needs:`.
      // Treat as a hard error rather than silently skipping.
      createPackage(tempDir, 'packages/foo', 'foo');
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
  foo:
    runs-on: ubuntu-latest
    steps:
      - run: echo
  required:
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });
  });
}
