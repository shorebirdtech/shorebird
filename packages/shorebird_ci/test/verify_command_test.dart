import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/action_versions.dart';
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/version.dart';
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

/// Runs `generate --style static` over [repoRoot], without the network
/// call that moves action pins to their latest release.
Future<void> runGenerateStatic(Directory repoRoot) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(GenerateCommand());
  final result = await runner.run([
    'generate',
    '--repo-root',
    repoRoot.path,
    '--style',
    'static',
    '--no-update-actions',
  ]);
  expect(result, 0);
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

  group('dynamic workflow and bloc_lint', () {
    const workflow = '''
# shorebird_ci-managed: dynamic
name: CI
on: [push]
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: shorebird_ci affected_packages --sdk dart
''';

    void addBlocLint(String relativePath) {
      File(
        p.join(tempDir.path, relativePath, 'pubspec.yaml'),
      ).writeAsStringSync(
        'dev_dependencies:\n  bloc_lint: ^0.3.0\n',
        mode: FileMode.append,
      );
    }

    test('fails when a package uses bloc_lint and nothing runs it', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      addBlocLint('packages/foo');
      _writeWorkflow(tempDir, 'ci.yaml', workflow);
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('passes when the workflow runs bloc lint', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      addBlocLint('packages/foo');
      _writeWorkflow(
        tempDir,
        'ci.yaml',
        '$workflow      - run: bloc lint .\n',
      );
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    });
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

  group('the shorebird_ci a workflow activates', () {
    // A package the workflow covers, so the only thing left to fail on is
    // the pin.
    void writeCoveredRepo(String activateLine) {
      createPackage(tempDir, 'packages/foo', 'foo');
      _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
$activateLine
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - packages/foo/**
''');
      initGitRepo(tempDir);
    }

    test('another version → returns 1', () async {
      writeCoveredRepo(
        '      - run: dart pub global activate shorebird_ci 0.1.0',
      );

      expect(await runVerify(tempDir), 1);
    });

    test('this version → passes', () async {
      writeCoveredRepo(
        '      - run: dart pub global activate shorebird_ci $packageVersion',
      );

      expect(await runVerify(tempDir), 0);
    });

    test('no version → passes, since CI runs the newest release', () async {
      writeCoveredRepo('      - run: dart pub global activate shorebird_ci');

      expect(await runVerify(tempDir), 0);
    });
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

  group('dep graph drift', () {
    void writeFooFilter(List<String> paths) {
      _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
${paths.map((path) => '              - $path').join('\n')}
            bar:
              - packages/bar/**
''');
    }

    setUp(() {
      createPackage(tempDir, 'packages/bar', 'bar');
      createPackage(
        tempDir,
        'packages/foo',
        'foo',
        dependencies: {'bar': '../bar'},
      );
    });

    test('filter missing a dependency → returns 1', () async {
      writeFooFilter(['packages/foo/**']);
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    test('filter covering every dependency → passes', () async {
      writeFooFilter(['packages/foo/**', './packages/bar/**']);
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    });

    test('an ancestor glob covers the dependency', () async {
      writeFooFilter(['packages/**']);
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 0);
    });

    test('a ! pattern does not cover the dependency', () async {
      writeFooFilter(['packages/foo/**', '!packages/bar/**']);
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });

    group('with bar a workspace member depended on by name', () {
      setUp(() {
        createWorkspaceRoot(
          tempDir,
          members: ['packages/foo', 'packages/bar'],
        );
        File(
          p.join(tempDir.path, 'packages', 'foo', 'pubspec.yaml'),
        ).writeAsStringSync('''
name: foo
resolution: workspace
environment:
  sdk: ^3.0.0
dependencies:
  bar: ^1.0.0
''');
      });

      test('filter missing it → returns 1', () async {
        writeFooFilter(['packages/foo/**', 'pubspec.lock', 'pubspec.yaml']);
        initGitRepo(tempDir);

        expect(await runVerify(tempDir), 1);
      });

      test('filter missing the workspace lockfile → returns 1', () async {
        writeFooFilter(['packages/foo/**', 'packages/bar/**', 'pubspec.yaml']);
        initGitRepo(tempDir);

        expect(await runVerify(tempDir), 1);
      });

      test('filter covering it → passes', () async {
        writeFooFilter([
          'packages/foo/**',
          'packages/bar/**',
          'pubspec.lock',
          './pubspec.yaml',
        ]);
        initGitRepo(tempDir);

        expect(await runVerify(tempDir), 0);
      });
    });

    test('each workflow filter must cover the dependency', () async {
      writeFooFilter(['packages/foo/**', 'packages/bar/**']);
      _writeWorkflow(tempDir, 'other.yaml', '''
name: Other
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - packages/foo/**
''');
      initGitRepo(tempDir);

      expect(await runVerify(tempDir), 1);
    });
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

    test(
      'checks submodule mount-point collapse and extraInputs in static filters',
      () async {
        File(p.join(tempDir.path, '.gitmodules')).writeAsStringSync('''
[submodule "vendor/sdk"]
\tpath = vendor/sdk
\turl = https://example.com/sdk.git
''');
        createPackage(tempDir, 'vendor/sdk/packages/helper', 'helper');
        final fooDir = Directory(p.join(tempDir.path, 'packages/foo'))
          ..createSync(recursive: true);
        File(p.join(fooDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: foo
environment:
  sdk: ^3.0.0
dependencies:
  helper:
    path: ../../vendor/sdk/packages/helper
shorebird_ci:
  inputs:
    - ../../openapi.yaml
    - scripts/**
''');
        initGitRepo(tempDir);

        // Missing vendor/sdk, openapi.yaml, and scripts/** -> fails with drift
        _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - packages/foo/**
''');
        expect(await runVerify(tempDir), 1);

        // Including vendor/sdk, openapi.yaml, and scripts/** -> passes
        _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            foo:
              - openapi.yaml
              - packages/foo/**
              - scripts/**
              - vendor/sdk
''');
        expect(await runVerify(tempDir), 0);
      },
    );
  });

  group('static regeneration drift', () {
    File orchestrator() => File(
      p.join(tempDir.path, '.github', 'workflows', 'shorebird_ci.yaml'),
    );

    /// Appends [line] to the `with:` block of `foo`'s job, the shape a
    /// per-package input takes when somebody adds one by hand instead of
    /// declaring it in the package's pubspec.
    void handAddInput(String line) {
      const anchor = '      package_name: foo\n';
      final content = orchestrator().readAsStringSync();
      expect(content, contains(anchor));
      orchestrator().writeAsStringSync(
        content.replaceFirst(anchor, '$anchor$line\n'),
      );
    }

    setUp(() {
      createWorkspaceRoot(tempDir, members: ['packages/bar', 'packages/foo']);
      createPackage(
        tempDir,
        'packages/foo',
        'foo',
        useWorkspace: true,
        addTestDir: true,
      );
      createPackage(
        tempDir,
        'packages/bar',
        'bar',
        useWorkspace: true,
        addTestDir: true,
      );
      initGitRepo(tempDir);
    });

    test('passes on a tree generation reproduces', () async {
      await runGenerateStatic(tempDir);

      expect(await runVerify(tempDir), 0);
    });

    test('fails on a hand-added min_coverage', () async {
      await runGenerateStatic(tempDir);
      handAddInput('      min_coverage: "90"');

      expect(await runVerify(tempDir), 1);
    });

    test('fails on a hand-added runners', () async {
      await runGenerateStatic(tempDir);
      handAddInput("      runners: '[\"macos-latest\"]'");

      expect(await runVerify(tempDir), 1);
    });

    test('fails on a hand-added needs_redis', () async {
      await runGenerateStatic(tempDir);
      handAddInput('      needs_redis: true');

      expect(await runVerify(tempDir), 1);
    });

    /// Writes the dynamic-coverage workflow that sits beside the
    /// orchestrator in a repo moving between the two styles.
    void writeDynamicWorkflow() {
      _writeWorkflow(tempDir, 'main.yaml', '''
# shorebird_ci-managed: dynamic
name: main
on: [push]
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - run: shorebird_ci affected_packages
''');
    }

    test('checks the orchestrator beside a dynamic workflow', () async {
      await runGenerateStatic(tempDir);
      writeDynamicWorkflow();

      expect(await runVerify(tempDir), 0);

      handAddInput('      min_coverage: "90"');

      expect(await runVerify(tempDir), 1);
    });

    test('checks an orchestrator carrying the dynamic marker', () async {
      await runGenerateStatic(tempDir);
      orchestrator().writeAsStringSync(
        '# shorebird_ci-managed: dynamic\n${orchestrator().readAsStringSync()}',
      );
      handAddInput('      min_coverage: "90"');

      expect(await runVerify(tempDir), 1);
    });

    test('fails on a difference too wide to print', () async {
      await runGenerateStatic(tempDir);
      handAddInput(
        List.generate(12, (i) => '      # hand-added $i').join('\n'),
      );

      expect(await runVerify(tempDir), 1);
    });

    test('passes once the hand-added input is declared instead', () async {
      File(
        p.join(tempDir.path, 'packages', 'foo', 'pubspec.yaml'),
      ).writeAsStringSync(
        'shorebird_ci:\n  min_coverage: 90\n',
        mode: FileMode.append,
      );
      await runGenerateStatic(tempDir);

      expect(
        orchestrator().readAsStringSync(),
        contains('      min_coverage: "90"'),
      );
      expect(await runVerify(tempDir), 0);
    });

    test('fails when a reusable workflow is deleted', () async {
      await runGenerateStatic(tempDir);
      File(
        p.join(
          tempDir.path,
          '.github',
          'workflows',
          '_shorebird_ci_dart.yaml',
        ),
      ).deleteSync();

      expect(await runVerify(tempDir), 1);
    });

    test('ignores an action pin Dependabot moved', () async {
      await runGenerateStatic(tempDir);
      final bumped = orchestrator().readAsStringSync().replaceAll(
        checkoutAction,
        'actions/checkout@${'f' * 40} # v99.0.0',
      );
      expect(bumped, isNot(orchestrator().readAsStringSync()));
      orchestrator().writeAsStringSync(bumped);

      expect(await runVerify(tempDir), 0);
    });

    test('reads --required and --fatal-infos from the root pubspec', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync(
        'shorebird_ci:\n  required: true\n  fatal_infos: true\n',
        mode: FileMode.append,
      );
      await runGenerateStatic(tempDir);

      expect(orchestrator().readAsStringSync(), contains('\n  required:\n'));
      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        contains('dart analyze --fatal-infos .'),
      );
      expect(await runVerify(tempDir), 0);
    });

    test('fails when a declared input is reverted in the workflow', () async {
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync(
        'shorebird_ci:\n  fatal_infos: true\n',
        mode: FileMode.append,
      );
      await runGenerateStatic(tempDir);
      final reusable = File(
        p.join(
          tempDir.path,
          '.github',
          'workflows',
          '_shorebird_ci_dart.yaml',
        ),
      );
      reusable.writeAsStringSync(
        reusable.readAsStringSync().replaceAll(
          '--fatal-infos',
          '--fatal-warnings',
        ),
      );

      expect(await runVerify(tempDir), 1);
    });

    test(
      'leaves a repo whose static workflows are hand-rolled alone',
      () async {
        _writeWorkflow(tempDir, 'ci.yaml', '''
name: CI
on: [push]
jobs:
  changes:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/paths-filter@v4
        with:
          filters: |
            bar:
              - packages/bar/**
              - pubspec.lock
              - pubspec.yaml
            foo:
              - packages/foo/**
              - pubspec.lock
              - pubspec.yaml
''');

        expect(await runVerify(tempDir), 0);
      },
    );
  });

  group('the filter suggested for a missing package', () {
    setUp(() {
      createWorkspaceRoot(tempDir, members: ['packages/foo']);
      createPackage(tempDir, 'packages/foo', 'foo', useWorkspace: true);
      initGitRepo(tempDir);
    });

    test('names the orchestrator and the reusable workflow it calls', () {
      final entries = suggestedFilterEntries(
        resolver: DependencyResolver(tempDir.path),
        packageDir: 'packages/foo',
        isFlutter: false,
        orchestratorPath: '.github/workflows/shorebird_ci.yaml',
      );

      expect(
        entries,
        containsAll([
          '.github/workflows/_shorebird_ci_dart.yaml',
          '.github/workflows/shorebird_ci.yaml',
          'packages/foo/**',
        ]),
      );
    });

    test('names the flutter reusable workflow for a flutter package', () {
      final entries = suggestedFilterEntries(
        resolver: DependencyResolver(tempDir.path),
        packageDir: 'packages/foo',
        isFlutter: true,
        orchestratorPath: '.github/workflows/shorebird_ci.yaml',
      );

      expect(
        entries,
        contains('.github/workflows/_shorebird_ci_flutter.yaml'),
      );
    });

    test('names no workflow when the static workflows are hand-rolled', () {
      final entries = suggestedFilterEntries(
        resolver: DependencyResolver(tempDir.path),
        packageDir: 'packages/foo',
        isFlutter: false,
        orchestratorPath: null,
      );

      expect(entries.where((e) => e.startsWith('.github/')), isEmpty);
    });
  });

  group('diffGeneratedWorkflow', () {
    test('returns null when the two match', () {
      expect(
        diffGeneratedWorkflow(expected: 'a\nb\n', actual: 'a\nb\n'),
        isNull,
      );
    });

    test('names the hand-added line and nothing around it', () {
      final diff = diffGeneratedWorkflow(
        expected: 'a\nb\nc\n',
        actual: 'a\n      min_coverage: "90"\nb\nc\n',
      );

      expect(diff, isNotNull);
      expect(diff!.line, 2);
      expect(diff.actual, ['      min_coverage: "90"']);
      expect(diff.expected, isEmpty);
    });

    test('names the line generation writes where one was removed', () {
      final diff = diffGeneratedWorkflow(
        expected: 'a\n      needs_redis: true\nb\n',
        actual: 'a\nb\n',
      );

      expect(diff!.actual, isEmpty);
      expect(diff.expected, ['      needs_redis: true']);
    });

    test('an action pinned to another commit is not a difference', () {
      expect(
        diffGeneratedWorkflow(
          expected: '      - uses: actions/checkout@aaa # v7.0.1\n',
          actual: '      - uses: actions/checkout@bbb # v7.1.0\n',
        ),
        isNull,
      );
    });

    test('a different action at the same step is a difference', () {
      expect(
        diffGeneratedWorkflow(
          expected: '      - uses: actions/checkout@aaa # v7.0.1\n',
          actual: '      - uses: other/checkout@aaa # v7.0.1\n',
        ),
        isNotNull,
      );
    });
  });
}
