import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/action_versions.dart';
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:shorebird_ci/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

/// Runs `generate` via the command runner.
///
/// Auto-bumping action versions is disabled by default so tests don't
/// hit the live GitHub API. Pass `--update-actions` in [extra] (along
/// with an injected resolver via the [GenerateCommand] constructor) to
/// exercise that path.
Future<int?> runGenerate(
  Directory repoRoot, {
  List<String> extra = const [],
  GenerateCommand? command,
}) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(command ?? GenerateCommand());
  return runner.run([
    'generate',
    '--repo-root',
    repoRoot.path,
    '--no-update-actions',
    ...extra,
  ]);
}

/// A generated Run Tests step, with the workflow and job holding it.
typedef TestSite = ({
  String name,
  String executable,
  String style,
  bool hasCodecov,
  String workflow,
  String job,
});

void main() {
  setUpTempDir('shorebird_ci_generate_');

  group('generate (dynamic, default)', () {
    test('emits a single workflow file', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      final mainYaml = File(
        p.join(tempDir.path, '.github', 'workflows', 'shorebird_ci.yaml'),
      );
      expect(mainYaml.existsSync(), isTrue);

      // No static reusables when dynamic.
      expect(
        File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('pins shorebird_ci to the version that generated it', () async {
      // Unpinned, every shorebird_ci release changes every generated
      // workflow the moment it's published.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      expect(
        _readMain(tempDir),
        contains(
          '      - run: dart pub global activate shorebird_ci '
          '$packageVersion\n',
        ),
      );
    });

    test('Dart-only repo gets only dart_ci job', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('dart_ci:'));
      expect(yaml, isNot(contains('flutter_ci:')));
    });

    test('Flutter-only repo gets only flutter_ci job', () async {
      createPackage(
        tempDir,
        'packages/foo',
        'foo',
        flutterLine: 'any',
      );
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('flutter_ci:'));
      expect(yaml, isNot(contains('dart_ci:')));
    });

    test('mixed repo gets both dart_ci and flutter_ci', () async {
      createPackage(tempDir, 'packages/dart_pkg', 'dart_pkg');
      createPackage(
        tempDir,
        'packages/flutter_pkg',
        'flutter_pkg',
        flutterLine: 'any',
      );
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('dart_ci:'));
      expect(yaml, contains('flutter_ci:'));
    });

    test('codecov detected → adds codecov upload step', () async {
      createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
      File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('codecov/codecov-action'));
      expect(yaml, contains('coverage:format_coverage'));
    });

    test('no codecov → no coverage steps', () async {
      createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, isNot(contains('codecov/codecov-action')));
      expect(yaml, isNot(contains('coverage:format_coverage')));
    });

    test('cspell config detected → adds cspell job', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('cspell:'));
      expect(
        yaml,
        matches(
          RegExp(
            r'run: npx --yes cspell@\d+\.\d+\.\d+ '
            r'--config \.cspell\.json --no-progress "\*\*"\n',
          ),
        ),
      );
      expect(yaml, contains('persist-credentials: false'));
      expect(yaml, isNot(contains('cspell-action')));
    });

    test('returns 1 when no packages discovered', () async {
      initGitRepo(tempDir);

      final code = await runGenerate(tempDir);

      expect(code, 1);
    });

    test('--dry-run does not write any files', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--dry-run']);

      // Neither the workflow nor dependabot.yml should be on disk.
      expect(
        File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            'shorebird_ci.yaml',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(tempDir.path, '.github', 'dependabot.yml'),
        ).existsSync(),
        isFalse,
      );
    });

    // Invariants: if the generator drops these strings, verify in the
    // generated workflow would silently misbehave at CI time. Catch
    // it here instead.
    test('output contains the markers verify recognizes', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      // verify recognizes dynamic coverage by looking for this string.
      expect(yaml, contains('shorebird_ci affected_packages'));
      // The verify step must itself be present in the generated workflow.
      expect(yaml, contains('shorebird_ci verify'));
    });

    test(
      'Dart analyze step emits --fatal-warnings explicitly',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        initGitRepo(tempDir);

        await runGenerate(tempDir);
        final yaml = _readMain(tempDir);

        expect(yaml, contains('dart analyze --fatal-warnings .'));
      },
    );

    test(
      'Flutter analyze step does not need --fatal-warnings (default on)',
      () async {
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir);
        final yaml = _readMain(tempDir);

        expect(yaml, contains('flutter analyze .'));
        expect(yaml, isNot(contains('flutter analyze --fatal-warnings')));
      },
    );

    test(
      '--codecov-token-secret threads token into codecov-action',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
        initGitRepo(tempDir);

        await runGenerate(
          tempDir,
          extra: ['--codecov-token-secret', 'CODECOV_TOKEN'],
        );
        final yaml = _readMain(tempDir);

        expect(yaml, contains(r'token: ${{ secrets.CODECOV_TOKEN }}'));
      },
    );

    test(
      'no --codecov-token-secret → no token plumbing emitted',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
        initGitRepo(tempDir);

        await runGenerate(tempDir);
        final yaml = _readMain(tempDir);

        // Asserting on `token:` alone is enough to prove the codecov
        // token plumbing didn't fire. A broader assertion on `secrets.`
        // would trip on any unrelated future step that references a
        // GitHub Actions secret.
        expect(yaml, isNot(contains('token:')));
      },
    );
  });

  group('generate --style static', () {
    test('emits main + dart reusable for Dart-only repo', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final workflows = p.join(tempDir.path, '.github', 'workflows');
      expect(
        File(p.join(workflows, 'shorebird_ci.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(workflows, '_shorebird_ci_dart.yaml')).existsSync(),
        isTrue,
      );
      // No flutter reusable when there are no flutter packages.
      expect(
        File(p.join(workflows, '_shorebird_ci_flutter.yaml')).existsSync(),
        isFalse,
      );
    });

    test('static filters include the workspace root pubspec files', () async {
      createWorkspaceRoot(tempDir, members: ['packages/foo']);
      createPackage(tempDir, 'packages/foo', 'foo', useWorkspace: true);
      createPackage(tempDir, 'tools/solo', 'solo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final content = File(
        p.join(tempDir.path, '.github', 'workflows', 'shorebird_ci.yaml'),
      ).readAsStringSync();
      expect(
        content,
        contains(
          '            foo:\n'
          '              - .github/workflows/_shorebird_ci_dart.yaml\n'
          '              - .github/workflows/shorebird_ci.yaml\n'
          '              - packages/foo/**\n'
          '              - pubspec.lock\n'
          '              - pubspec.yaml\n',
        ),
      );
      expect(
        content,
        contains(
          '            solo:\n'
          '              - .github/workflows/_shorebird_ci_dart.yaml\n'
          '              - .github/workflows/shorebird_ci.yaml\n'
          '              - tools/solo/**\n',
        ),
      );
    });

    test('every static filter matches the orchestrator itself', () async {
      // Every package's job is declared in the orchestrator, so a commit
      // touching only it would skip every job a filter that misses it.
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar');
      createPackage(tempDir, 'packages/baz', 'baz', flutterLine: 'any');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final filters = _readStaticFilters(_readMain(tempDir));
      expect(filters.keys, containsAll(['bar', 'baz', 'foo']));
      for (final MapEntry(key: slug, value: paths) in filters.entries) {
        expect(
          paths,
          contains('.github/workflows/shorebird_ci.yaml'),
          reason: slug,
        );
      }
    });

    test('every static filter matches a custom --output path', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--output', '.github/workflows/ci.yaml'],
      );

      final filters = _readStaticFilters(readWorkflow('ci.yaml'));
      expect(filters['foo'], contains('.github/workflows/ci.yaml'));
      expect(
        filters['foo'],
        isNot(contains('.github/workflows/shorebird_ci.yaml')),
      );
    });

    test('static workflow pins shorebird_ci to its version', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(
        _readMain(tempDir),
        contains(
          '      - run: dart pub global activate shorebird_ci '
          '$packageVersion\n',
        ),
      );
    });

    test('static workflow triggers on merge_group', () async {
      // Branch protection's required contexts only gate a merge if they
      // report on the queue's temp branch too.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final yaml = _readMain(tempDir);
      expect(yaml, contains('  merge_group:\n    types: [checks_requested]'));
    });

    test('static workflow cancels a superseded PR run', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final yaml = _readMain(tempDir);
      _expectPrOnlyConcurrency(yaml);
    });

    test('every workflow gets a read-only token', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final workflows = Directory(p.join(tempDir.path, '.github', 'workflows'));
      for (final name in [
        'shorebird_ci.yaml',
        '_shorebird_ci_dart.yaml',
        '_shorebird_ci_flutter.yaml',
      ]) {
        final doc =
            loadYaml(File(p.join(workflows.path, name)).readAsStringSync())
                as YamlMap;
        expect(doc['permissions'], {'contents': 'read'}, reason: name);
      }
    });

    test('only the changes job gets more than the workflow token', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static', '--required']);

      final jobs = _expectReadOnlyJobs(tempDir, except: 'changes');
      expect((jobs['changes']! as YamlMap)['permissions'], {
        'contents': 'read',
        'pull-requests': 'read',
      });
    });

    test('emits main + both reusables for mixed repo', () async {
      createPackage(tempDir, 'packages/dart_pkg', 'dart_pkg');
      createPackage(
        tempDir,
        'packages/flutter_pkg',
        'flutter_pkg',
        flutterLine: 'any',
      );
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final workflows = p.join(tempDir.path, '.github', 'workflows');
      expect(
        File(p.join(workflows, '_shorebird_ci_dart.yaml')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(workflows, '_shorebird_ci_flutter.yaml')).existsSync(),
        isTrue,
      );
    });

    test(
      'main workflow uses dorny/paths-filter and per-package jobs',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        createPackage(
          tempDir,
          'packages/bar',
          'bar',
          dependencies: {'foo': '../foo'},
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final yaml = _readMain(tempDir);

        expect(yaml, contains('dorny/paths-filter'));
        expect(yaml, contains('foo:'));
        expect(yaml, contains('bar:'));
        // bar depends on foo, so bar's filter should include foo's path.
        expect(
          yaml,
          matches(RegExp(r'bar:[^#]*packages/foo/\*\*', dotAll: true)),
        );
      },
    );

    test(
      'has_unit_tests gates the test + codecov steps',
      () async {
        // Two packages: one with a test/ dir, one without. The main
        // workflow should pass has_unit_tests per package, and the
        // reusable workflow should gate its test step on the input.
        createPackage(
          tempDir,
          'packages/with_tests',
          'with_tests',
          addTestDir: true,
        );
        createPackage(tempDir, 'packages/no_tests', 'no_tests');
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);

        final main = _readMain(tempDir);
        expect(
          main,
          matches(
            RegExp(
              'with_tests:[^#]*has_unit_tests: true',
              dotAll: true,
            ),
          ),
        );
        expect(
          main,
          matches(
            RegExp(
              'no_tests:[^#]*has_unit_tests: false',
              dotAll: true,
            ),
          ),
        );

        final reusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).readAsStringSync();
        expect(reusable, contains('has_unit_tests:'));
        expect(reusable, contains('if: inputs.has_unit_tests'));
      },
    );

    test(
      'YAML map keys default to the package name when unique',
      () async {
        // A repo where every package has a unique `name:` — the YAML
        // keys are just the names, no path prefix.
        createPackage(tempDir, 'packages/foo', 'foo');
        createPackage(tempDir, 'apps/bar', 'bar');
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final yaml = _readMain(tempDir);

        for (final slug in ['foo', 'bar']) {
          expect(yaml, contains('$slug:'));
          expect(yaml, contains('needs.changes.outputs.$slug'));
        }
        // No path-prefixed variants leak in.
        expect(yaml, isNot(contains('packages_foo')));
        expect(yaml, isNot(contains('apps_bar')));
      },
    );

    test(
      'YAML map keys fall back to <parent>_<name> on collision',
      () async {
        // Two packages w/ the same `name:` at different parent dirs:
        // pub allows this, and shorebird_ci must disambiguate the YAML
        // keys by walking up one path segment. `name: harness` under
        // `apps/alpha/` becomes `alpha_harness`, under `apps/beta/`
        // becomes `beta_harness`. A unique-named neighbor in the same
        // repo keeps its plain name.
        createPackage(tempDir, 'apps/alpha/harness', 'harness');
        createPackage(tempDir, 'apps/beta/harness', 'harness');
        createPackage(tempDir, 'packages/foo', 'foo');
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final yaml = _readMain(tempDir);

        for (final slug in ['alpha_harness', 'beta_harness', 'foo']) {
          // Each slug appears as a dorny filter key, an outputs entry,
          // and a per-package job key.
          expect(yaml, contains('$slug:'));
          expect(yaml, contains('needs.changes.outputs.$slug'));
        }
        // The actual package name still flows through as the
        // `package_name:` input value (used for codecov flags).
        expect(yaml, contains('package_name: harness'));
        expect(yaml, contains('package_name: foo'));
        // The unique package does not get prefixed.
        expect(yaml, isNot(contains('packages_foo')));
      },
    );

    test('verify step comes before dorny filter', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);
      final yaml = _readMain(tempDir);

      final verifyIdx = yaml.indexOf('shorebird_ci verify');
      final dornyIdx = yaml.indexOf('dorny/paths-filter');
      expect(verifyIdx, greaterThan(-1));
      expect(dornyIdx, greaterThan(-1));
      expect(verifyIdx, lessThan(dornyIdx));
    });

    test('cspell config detected → adds cspell job in static mode', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('cspell:'));
      expect(
        yaml,
        matches(
          RegExp(
            r'run: npx --yes cspell@\d+\.\d+\.\d+ '
            r'--config \.cspell\.json --no-progress "\*\*"\n',
          ),
        ),
      );
      expect(yaml, contains('persist-credentials: false'));
      expect(yaml, isNot(contains('cspell-action')));
    });

    test(
      'Dart reusable analyze step emits --fatal-warnings explicitly',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final dartReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).readAsStringSync();

        expect(dartReusable, contains('dart analyze --fatal-warnings .'));
      },
    );

    test(
      'Flutter reusable analyze step does not need --fatal-warnings',
      () async {
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final flutterReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_flutter.yaml',
          ),
        ).readAsStringSync();

        expect(flutterReusable, contains('flutter analyze .'));
        expect(
          flutterReusable,
          isNot(contains('flutter analyze --fatal-warnings')),
        );
      },
    );

    test(
      '--codecov-token-secret emits secrets: inherit on each '
      'orchestrator uses: call and threads token into reusable',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
          addTestDir: true,
        );
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
        initGitRepo(tempDir);

        await runGenerate(
          tempDir,
          extra: [
            '--style',
            'static',
            '--codecov-token-secret',
            'CODECOV_TOKEN',
          ],
        );
        final mainYaml = _readMain(tempDir);
        final dartReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).readAsStringSync();
        final flutterReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_flutter.yaml',
          ),
        ).readAsStringSync();

        // One `secrets: inherit` per package job (2 packages).
        expect(
          'secrets: inherit'.allMatches(mainYaml).length,
          equals(2),
        );
        expect(
          dartReusable,
          contains(r'token: ${{ secrets.CODECOV_TOKEN }}'),
        );
        expect(
          flutterReusable,
          contains(r'token: ${{ secrets.CODECOV_TOKEN }}'),
        );
      },
    );

    test(
      'no --codecov-token-secret → no secrets: inherit, no token',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final mainYaml = _readMain(tempDir);
        final dartReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).readAsStringSync();

        expect(mainYaml, isNot(contains('secrets: inherit')));
        expect(dartReusable, isNot(contains('token:')));
      },
    );

    test(
      '--codecov-token-secret w/o codecov config → no plumbing emitted',
      () async {
        // Repo has no codecov config, so reusable workflow has no
        // codecov-action step. The flag should be a no-op here even
        // when passed.
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        initGitRepo(tempDir);

        await runGenerate(
          tempDir,
          extra: [
            '--style',
            'static',
            '--codecov-token-secret',
            'CODECOV_TOKEN',
          ],
        );
        final mainYaml = _readMain(tempDir);

        expect(mainYaml, isNot(contains('secrets: inherit')));
      },
    );

    test(
      '--codecov-token-secret accepts an arbitrary secret name',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
        initGitRepo(tempDir);

        await runGenerate(
          tempDir,
          extra: [
            '--style',
            'static',
            '--codecov-token-secret',
            'MY_CUSTOM_NAME',
          ],
        );
        final dartReusable = File(
          p.join(
            tempDir.path,
            '.github',
            'workflows',
            '_shorebird_ci_dart.yaml',
          ),
        ).readAsStringSync();

        expect(
          dartReusable,
          contains(r'token: ${{ secrets.MY_CUSTOM_NAME }}'),
        );
      },
    );
  });

  group('bloc lint', () {
    /// Gives the package at [relativePath] a bloc_lint dev dependency.
    void addBlocLint(String relativePath) {
      File(
        p.join(tempDir.path, relativePath, 'pubspec.yaml'),
      ).writeAsStringSync(
        'dev_dependencies:\n  bloc_lint: ^0.3.0\n',
        mode: FileMode.append,
      );
    }

    test('dynamic: no bloc steps when no package uses bloc_lint', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      final yaml = _readMain(tempDir);
      expect(yaml, isNot(contains('bloc')));
    });

    test('dynamic: bloc steps only in the job whose SDK uses it', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      addBlocLint('packages/bar');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      final yaml = loadYaml(_readMain(tempDir)) as YamlMap;
      final jobs = yaml['jobs'] as YamlMap;
      List<Object?> stepNames(String job) => [
        for (final step in (jobs[job] as YamlMap)['steps'] as YamlList)
          (step as YamlMap)['name'],
      ];
      expect(stepNames('flutter_ci'), contains('Setup Bloc Tools'));
      expect(stepNames('flutter_ci'), contains('Bloc Lint'));
      expect(stepNames('dart_ci'), isNot(contains('Setup Bloc Tools')));
      expect(stepNames('dart_ci'), isNot(contains('Bloc Lint')));
    });

    test('static: no bloc input or steps when no package uses it', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(_readMain(tempDir), isNot(contains('bloc')));
      expect(readWorkflow('_shorebird_ci_dart.yaml'), isNot(contains('bloc')));
      expect(
        readWorkflow('_shorebird_ci_flutter.yaml'),
        isNot(contains('bloc')),
      );
    });

    test('static: passes has_bloc_lint only to packages that use it', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/baz', 'baz');
      addBlocLint('packages/baz');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final jobs = (loadYaml(_readMain(tempDir)) as YamlMap)['jobs'] as YamlMap;
      YamlMap withOf(String job) => (jobs[job] as YamlMap)['with'] as YamlMap;
      expect(withOf('baz')['has_bloc_lint'], isTrue);
      expect(withOf('foo').containsKey('has_bloc_lint'), isFalse);

      final dart = readWorkflow('_shorebird_ci_dart.yaml');
      expect(dart, contains('has_bloc_lint:'));
      expect(
        dart,
        matches(
          RegExp(
            r'run: dart pub global activate bloc_tools \d+\.\d+\.\d+\S*\n',
          ),
        ),
      );
      expect(dart, contains('run: bloc lint .'));
      expect(
        readWorkflow('_shorebird_ci_flutter.yaml'),
        isNot(contains('bloc')),
      );
    });

    test('static: Flutter-only bloc goes to the Flutter reusable', () async {
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      addBlocLint('packages/bar');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      final flutter = readWorkflow('_shorebird_ci_flutter.yaml');
      final inputs =
          ((loadYaml(flutter) as YamlMap)['on'] as YamlMap)['workflow_call']
              as YamlMap;
      expect((inputs['inputs'] as YamlMap).containsKey('has_bloc_lint'), true);
      expect(
        flutter,
        matches(
          RegExp(
            r'run: dart pub global activate bloc_tools \d+\.\d+\.\d+\S*\n',
          ),
        ),
      );
      expect(flutter, contains('run: bloc lint .'));
    });
  });

  group('dependabot.yml', () {
    test('creates dependabot.yml when missing', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      final dependabotFile = File(
        p.join(tempDir.path, '.github', 'dependabot.yml'),
      );
      expect(dependabotFile.existsSync(), isTrue);
      expect(dependabotFile.readAsStringSync(), contains('github-actions'));
    });

    test('exposes a non-empty description', () {
      expect(GenerateCommand().description, isNotEmpty);
    });

    test('leaves existing dependabot.yml alone', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      final githubDir = Directory(p.join(tempDir.path, '.github'))
        ..createSync(recursive: true);
      final existing = File(p.join(githubDir.path, 'dependabot.yml'))
        ..writeAsStringSync('# user content\nversion: 2\n');
      initGitRepo(tempDir);

      await runGenerate(tempDir);

      expect(
        existing.readAsStringSync(),
        equals('# user content\nversion: 2\n'),
      );
    });
  });

  group('--update-actions (auto-bump)', () {
    // cspell:disable-next-line
    const sha99 = 'abcdefabcdefabcdefabcdefabcdefabcdef9999';
    Future<ActionRelease?> resolve99(String _) async =>
        const ActionRelease(tag: 'v99.0.0', sha: sha99);

    test('pins each action to its latest release when enabled', () async {
      // Inject a resolver that reports v99 for every action so we can
      // confirm the post-write step actually runs and mutates the file.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(GenerateCommand(resolveLatestRelease: resolve99));
      final code = await runner.run([
        'generate',
        '--repo-root',
        tempDir.path,
        // No --no-update-actions here — auto-bump is the default.
      ]);

      expect(code, 0);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('uses: actions/checkout@$sha99 # v99.0.0'));
      expect(yaml, contains('uses: dart-lang/setup-dart@$sha99 # v99.0.0'));
    });

    test('--no-update-actions writes the built-in SHA pins', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      // Resolver would bump to v99 if called; --no-update-actions should
      // prevent that, leaving the generator's built-in pins untouched.
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(GenerateCommand(resolveLatestRelease: resolve99));
      final code = await runner.run([
        'generate',
        '--repo-root',
        tempDir.path,
        '--no-update-actions',
      ]);

      expect(code, 0);
      final yaml = _readMain(tempDir);
      expect(yaml, isNot(contains('v99')));
      expect(yaml, contains('uses: $checkoutAction'));
    });

    test('every generated uses: ref is pinned to a commit SHA', () async {
      // Covers both styles, Flutter and Dart, codecov, bloc and cspell,
      // so every action the templates can emit is checked.
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      for (final pkg in ['foo', 'bar']) {
        File(
          p.join(tempDir.path, 'packages', pkg, 'pubspec.yaml'),
        ).writeAsStringSync(
          'dev_dependencies:\n  bloc_lint: ^0.3.0\n',
          mode: FileMode.append,
        );
      }
      File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      File(p.join(tempDir.path, 'cspell.config.yaml')).writeAsStringSync('');
      initGitRepo(tempDir);

      final usesLine = RegExp(r'uses:\s+(\S+)(.*)');
      final pinned = RegExp(r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$');
      for (final style in ['dynamic', 'static']) {
        final runner = CommandRunner<int>('test', 'test')
          ..addCommand(GenerateCommand());
        final code = await runner.run([
          'generate',
          '--repo-root',
          tempDir.path,
          '--style',
          style,
          '--no-update-actions',
        ]);
        expect(code, 0);
        final dir = Directory(p.join(tempDir.path, '.github', 'workflows'));
        final repos = <String>{};
        for (final file in dir.listSync().whereType<File>()) {
          for (final m in usesLine.allMatches(file.readAsStringSync())) {
            final ref = m.group(1)!;
            if (ref.startsWith('./')) continue;
            repos.add(ref.split('@').first);
            expect(ref, matches(pinned), reason: '${file.path}: $ref');
            expect(m.group(2), matches(RegExp(r'^ # v\d+\.\d+\.\d+$')));
          }
        }
        expect(unpinnedActionRefs(_readAll(dir)), isEmpty);
        // Every action the templates can emit showed up, so each was
        // checked.
        expect(
          repos,
          containsAll([
            'actions/checkout',
            'dart-lang/setup-dart',
            'codecov/codecov-action',
            'subosito/flutter-action',
            if (style == 'static') 'dorny/paths-filter',
          ]),
        );
      }
    });
  });

  group('setup-job runner ergonomics', () {
    test('dynamic workflow triggers on merge_group', () async {
      // Branch protection's required contexts only gate a merge if they
      // report on the queue's temp branch too.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('  merge_group:\n    types: [checks_requested]'));
    });

    test('dynamic workflow cancels a superseded PR run', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      _expectPrOnlyConcurrency(yaml);
    });

    test('dynamic workflow gets a read-only token', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final doc = loadYaml(_readMain(tempDir)) as YamlMap;
      expect(doc['permissions'], {'contents': 'read'});
    });

    test('dynamic jobs get no more than the workflow token', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar', flutterLine: 'any');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);
      await runGenerate(tempDir, extra: ['--required']);
      _expectReadOnlyJobs(tempDir);
    });

    test('dynamic workflow has workflow_dispatch trigger', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('workflow_dispatch:'));
    });

    test('dynamic setup job pins fetch-depth: 0', () async {
      // Without full history, affected_packages can't diff against
      // origin/main on the runner.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('fetch-depth: 0'));
    });

    test('dynamic setup passes --all on workflow_dispatch', () async {
      // Manual dispatch should bypass the diff and run every package.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('EXTRA_ARGS=--all'));
      expect(yaml, contains(r'affected_packages --sdk dart $EXTRA_ARGS'));
    });

    test('dynamic setup logs a hint when diff yields no packages', () async {
      // On push to main, HEAD == origin/main and the diff is empty.
      // The workflow should tell the user about the manual button.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(yaml, contains("Click 'Run workflow' in the Actions tab"));
    });

    test('generated dynamic workflow is valid YAML', () async {
      // Regression guard: a bash `\` continuation that drops to column 0
      // inside a `run: |` block silently breaks the YAML literal and
      // the runner rejects the file. loadYaml catches this locally.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);
      expect(() => loadYaml(yaml), returnsNormally);
    });

    test('static main yaml pins fetch-depth: 0', () async {
      // dorny/paths-filter on push events needs full history.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(GenerateCommand(resolveLatestRelease: (_) async => null));
      await runner.run([
        'generate',
        '--repo-root',
        tempDir.path,
        '--style',
        'static',
        '--no-update-actions',
      ]);
      final yaml = _readMain(tempDir);
      expect(yaml, contains('fetch-depth: 0'));
    });
  });

  group('--required aggregator job', () {
    test('omitted by default in static mode', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);
      final yaml = _readMain(tempDir);

      expect(yaml, isNot(contains('required:')));
    });

    test('omitted by default in dynamic mode', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir);
      final yaml = _readMain(tempDir);

      expect(yaml, isNot(contains('  required:')));
    });

    test('static --required depends on changes + every package job', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar');
      initGitRepo(tempDir);

      await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--required'],
      );
      final yaml = _readMain(tempDir);

      expect(yaml, contains('  required:'));
      // `needs:` lists changes + every per-package slug.
      expect(
        yaml,
        matches(
          RegExp(
            'required:[^#]*needs:[^#]*- changes[^#]*- bar[^#]*- foo',
            dotAll: true,
          ),
        ),
      );
      // Runs unless the run was cancelled (a superseded PR head), and
      // treats skipped sub-jobs as success.
      expect(yaml, contains(r'if: ${{ !cancelled() }}'));
      expect(yaml, contains("contains(needs.*.result, 'failure')"));
      expect(yaml, contains("contains(needs.*.result, 'cancelled')"));
    });

    test('static --required includes cspell when present', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);

      await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--required'],
      );
      final yaml = _readMain(tempDir);

      expect(
        yaml,
        matches(
          RegExp(
            'required:[^#]*needs:[^#]*- cspell',
            dotAll: true,
          ),
        ),
      );
    });

    test('dynamic --required depends on setup + matrix jobs', () async {
      createPackage(tempDir, 'packages/dart_pkg', 'dart_pkg');
      createPackage(
        tempDir,
        'packages/flutter_pkg',
        'flutter_pkg',
        flutterLine: 'any',
      );
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--required']);
      final yaml = _readMain(tempDir);

      expect(yaml, contains('  required:'));
      expect(
        yaml,
        matches(
          RegExp(
            'required:[^#]*needs:[^#]*- setup[^#]*'
            '- dart_ci[^#]*- flutter_ci',
            dotAll: true,
          ),
        ),
      );
    });

    test('dynamic --required includes cspell when present', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(p.join(tempDir.path, '.cspell.json')).writeAsStringSync('{}');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--required']);
      final yaml = _readMain(tempDir);

      expect(
        yaml,
        matches(
          RegExp(
            'required:[^#]*needs:[^#]*- cspell',
            dotAll: true,
          ),
        ),
      );
    });

    test('generated workflow with --required is valid YAML', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--required'],
      );
      final yaml = _readMain(tempDir);
      expect(() => loadYaml(yaml), returnsNormally);
    });

    test('--required + package named `required` → fails at generate', () async {
      // `required` is the reserved aggregator job key. A package slug
      // that resolves to `required` would duplicate the YAML key and
      // silently overwrite the aggregator. Generate must refuse.
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/required', 'required');
      initGitRepo(tempDir);

      final exitCode = await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--required'],
      );

      expect(exitCode, 1);
    });

    test(
      '--required + package named `required` is fine in dynamic mode',
      () async {
        // Dynamic mode keys jobs by `setup` / `dart_ci` / `flutter_ci`
        // / `cspell`, never by per-package slug, so a package named
        // `required` cannot collide w/ the aggregator. The collision
        // check only fires for --style static.
        createPackage(tempDir, 'packages/required', 'required');
        initGitRepo(tempDir);

        final exitCode = await runGenerate(
          tempDir,
          extra: ['--required'],
        );

        expect(exitCode, 0);
      },
    );

    test('collision check does not fire when --required is absent', () async {
      // The reserved-name contract only applies when the user opts into
      // the aggregator. A package named `required` is fine on its own.
      createPackage(tempDir, 'packages/required', 'required');
      initGitRepo(tempDir);

      final exitCode = await runGenerate(
        tempDir,
        extra: ['--style', 'static'],
      );

      expect(exitCode, 0);
    });
  });

  group('v0.3.0 features', () {
    test('--filters-only updates dorny/paths-filter in place', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar');
      final workflowsDir = Directory(
        p.join(tempDir.path, '.github', 'workflows'),
      )..createSync(recursive: true);
      final workflowFile = File(p.join(workflowsDir.path, 'shorebird_ci.yaml'))
        ..writeAsStringSync('''
name: Custom CI
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            foo:
              - old/path/**
  custom_job:
    runs-on: ubuntu-latest
    steps:
      - run: echo "preserved"
''');
      initGitRepo(tempDir);

      final exitCode = await runGenerate(
        tempDir,
        extra: ['--filters-only'],
      );
      expect(exitCode, 0);

      final updated = workflowFile.readAsStringSync();
      expect(updated, contains('name: Custom CI'));
      expect(updated, contains('custom_job:'));
      expect(
        updated,
        contains(
          '          filters: |\n'
          '            bar:\n'
          '              - .github/workflows/shorebird_ci.yaml\n'
          '              - packages/bar/**\n'
          '            foo:\n'
          '              - .github/workflows/shorebird_ci.yaml\n'
          '              - packages/foo/**\n',
        ),
      );
    });

    test('--filters-only --dry-run does not modify disk', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      final workflowsDir = Directory(
        p.join(tempDir.path, '.github', 'workflows'),
      )..createSync(recursive: true);
      const original = '''
name: Custom CI
jobs:
  changes:
    steps:
      - uses: dorny/paths-filter@v3
        with:
          filters: |
            foo:
              - old/path/**
''';
      final workflowFile = File(p.join(workflowsDir.path, 'shorebird_ci.yaml'))
        ..writeAsStringSync(original);
      initGitRepo(tempDir);

      final exitCode = await runGenerate(
        tempDir,
        extra: ['--filters-only', '--dry-run'],
      );
      expect(exitCode, 0);
      expect(workflowFile.readAsStringSync(), original);
    });

    test('--filters-only fails when workflow file is missing', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      final exitCode = await runGenerate(
        tempDir,
        extra: ['--filters-only'],
      );
      expect(exitCode, 1);
    });

    test(
      '--filters-only fails when workflow has no filters: | block',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        final workflowsDir = Directory(
          p.join(tempDir.path, '.github', 'workflows'),
        )..createSync(recursive: true);
        File(
          p.join(workflowsDir.path, 'shorebird_ci.yaml'),
        ).writeAsStringSync('name: CI\njobs: {}\n');
        initGitRepo(tempDir);

        final exitCode = await runGenerate(
          tempDir,
          extra: ['--filters-only'],
        );
        expect(exitCode, 1);
      },
    );

    test(
      '--fatal-infos appends --fatal-infos in static and dynamic modes',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
        );
        initGitRepo(tempDir);

        await runGenerate(
          tempDir,
          extra: ['--style', 'static', '--fatal-infos'],
        );
        expect(
          readWorkflow('_shorebird_ci_dart.yaml'),
          contains('dart analyze --fatal-infos .'),
        );
        expect(
          readWorkflow('_shorebird_ci_flutter.yaml'),
          contains('flutter analyze --fatal-infos .'),
        );

        await runGenerate(tempDir, extra: ['--fatal-infos']);
        final dynamicYaml = _readMain(tempDir);
        expect(
          dynamicYaml,
          contains('dart analyze --fatal-infos .'),
        );
        expect(dynamicYaml, contains('flutter analyze --fatal-infos .'));
      },
    );

    test(
      'submodules: recursive is emitted only when .gitmodules exists',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo');
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        expect(
          readWorkflow('_shorebird_ci_dart.yaml'),
          isNot(contains('submodules: recursive')),
        );
        expect(
          readWorkflow('_shorebird_ci_flutter.yaml'),
          isNot(contains('submodules: recursive')),
        );

        File(p.join(tempDir.path, '.gitmodules')).writeAsStringSync(
          '[submodule "sub"]\n\tpath = sub\n',
        );
        await runGenerate(tempDir, extra: ['--style', 'static']);
        expect(
          readWorkflow('_shorebird_ci_dart.yaml'),
          contains('submodules: recursive'),
        );
        expect(
          readWorkflow('_shorebird_ci_flutter.yaml'),
          contains('submodules: recursive'),
        );

        await runGenerate(tempDir);
        expect(_readMain(tempDir), contains('submodules: recursive'));
      },
    );

    test('dorny/paths-filter passes merge_group base_ref', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);
      expect(
        _readMain(tempDir),
        contains(r"base: ${{ github.event.merge_group.base_ref || '' }}"),
      );
    });

    test(
      'declarative shorebird_ci pubspec config flows into static jobs',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        File(
          p.join(tempDir.path, 'packages/foo/pubspec.yaml'),
        ).writeAsStringSync(
          '''
shorebird_ci:
  min_coverage: 100
  runners:
    - ubuntu-latest
    - macos-latest
    - windows-latest
  needs_redis: true
  report_on: lib/ bin/ routes/
  coverage_excludes: "**/*.g.dart **/*.freezed.dart"
  total_shards: 4
''',
          mode: FileMode.append,
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final mainYaml = _readMain(tempDir);
        expect(mainYaml, contains('min_coverage: "100"'));
        expect(
          mainYaml,
          contains(
            'runners: \'["ubuntu-latest", "macos-latest", "windows-latest"]\'',
          ),
        );
        expect(mainYaml, contains('needs_redis: true'));
        expect(mainYaml, contains('report_on: "lib/ bin/ routes/"'));
        expect(
          mainYaml,
          contains('coverage_excludes: "**/*.g.dart **/*.freezed.dart"'),
        );
        expect(mainYaml, contains('total_shards: 4'));
        expect(
          readWorkflow('_shorebird_ci_dart.yaml'),
          contains('redis/redis-stack-server:latest'),
        );
      },
    );

    test(
      'reusable workflows contain matrix, coverage, sharding, and routes',
      () async {
        createPackage(tempDir, 'packages/foo', 'foo', addTestDir: true);
        createPackage(
          tempDir,
          'packages/flutter_pkg',
          'flutter_pkg',
          flutterLine: 'any',
          addTestDir: true,
        );
        initGitRepo(tempDir);

        await runGenerate(tempDir, extra: ['--style', 'static']);
        final dartYaml = readWorkflow('_shorebird_ci_dart.yaml');
        final flutterYaml = readWorkflow('_shorebird_ci_flutter.yaml');

        for (final yaml in [dartYaml, flutterYaml]) {
          expect(
            yaml,
            contains(
              r"os: ${{ fromJSON(github.event_name == 'pull_request' && "
              '\'["ubuntu-latest"]\' || inputs.runners) }}',
            ),
          );
          expect(yaml, contains('defaults:\n      run:\n        shell: bash'));
          expect(yaml, contains('set -f'));
          expect(yaml, contains('xargs -n 50'));
          expect(
            yaml,
            contains(r'COVERAGE_DIR="$(pwd -W 2>/dev/null || pwd)/coverage"'),
          );
          expect(
            yaml,
            contains(
              'shorebird_ci check_coverage coverage/lcov.info '
              r'--min "$MIN_COVERAGE"',
            ),
          );
          expect(() => loadYaml(yaml), returnsNormally);
        }

        expect(dartYaml, contains('package_config_scoped.json'));
        expect(dartYaml, contains('routes/.well-known'));
      },
    );
  });

  group('Run Tests step', () {
    /// Every generated step the retry wraps.
    const sites = <TestSite>[
      (
        name: 'static dart',
        executable: 'dart',
        style: 'static',
        hasCodecov: false,
        workflow: '_shorebird_ci_dart.yaml',
        job: 'ci',
      ),
      (
        name: 'static flutter',
        executable: 'flutter',
        style: 'static',
        hasCodecov: false,
        workflow: '_shorebird_ci_flutter.yaml',
        job: 'ci',
      ),
      (
        name: 'dynamic dart',
        executable: 'dart',
        style: 'dynamic',
        hasCodecov: true,
        workflow: 'shorebird_ci.yaml',
        job: 'dart_ci',
      ),
      (
        name: 'dynamic flutter',
        executable: 'flutter',
        style: 'dynamic',
        hasCodecov: true,
        workflow: 'shorebird_ci.yaml',
        job: 'flutter_ci',
      ),
    ];

    /// The `run:` script of the Run Tests step in [job] of [workflow].
    String runTestsStep(String workflow, String job) {
      final steps =
          ((loadYaml(workflow) as YamlMap)['jobs'] as YamlMap)[job] as YamlMap;
      final step = (steps['steps'] as YamlList).cast<YamlMap>().firstWhere(
        (step) => step['name'] == 'Run Tests',
      );
      return step['run'] as String;
    }

    /// Writes an [executable] into [dir] that answers each `test` invocation
    /// with the next entry of [runs] and every other invocation with success,
    /// recording the `test` ones in `attempts` beside itself. The last entry
    /// answers every `test` invocation after it.
    void writeStub(
      Directory dir,
      String executable,
      List<({String output, int exitCode})> runs,
    ) {
      final cases = [
        for (final (index, run) in runs.indexed)
          '''
  ${index == runs.length - 1 ? '*' : index + 1})
    printf '%s\\n' '${run.output}'
    exit ${run.exitCode}
    ;;''',
      ].join('\n');
      final stub = File(p.join(dir.path, executable))
        ..writeAsStringSync('''
#!/usr/bin/env bash
if [ "\$1" != test ]; then
  exit 0
fi
attempts="\$(dirname "\$0")/attempts"
echo "$executable \$*" >> "\$attempts"
case "\$(grep -c . "\$attempts")" in
$cases
esac
''');
      Process.runSync('chmod', ['+x', stub.path]);
    }

    /// Runs [site]'s generated step over one test file, against an SDK
    /// answering with [runs]. Returns the step's exit code and how many
    /// times it ran the SDK's `test`.
    Future<({int exitCode, int testRuns})> runStep(
      TestSite site,
      List<({String output, int exitCode})> runs,
    ) async {
      final isFlutter = site.executable == 'flutter';
      createPackage(
        tempDir,
        'pkg',
        'pkg',
        addTestDir: true,
        flutterLine: isFlutter ? 'any' : null,
      );
      if (site.hasCodecov) {
        File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      }
      initGitRepo(tempDir);
      await runGenerate(tempDir, extra: ['--style', site.style]);

      final stubDir = Directory(p.join(tempDir.path, 'stub'))..createSync();
      writeStub(stubDir, site.executable, runs);
      final script = File(p.join(tempDir.path, 'step.sh'))
        ..writeAsStringSync(
          runTestsStep(readWorkflow(site.workflow), site.job),
        );

      // The static workflows declare `shell: bash`, which GitHub runs with
      // `-eo pipefail`. The dynamic ones take the default `bash -e`, so the
      // step cannot lean on its caller for pipefail.
      final result = Process.runSync(
        'bash',
        [
          '--noprofile',
          '--norc',
          if (site.style == 'static') ...['-eo', 'pipefail'] else '-e',
          script.path,
        ],
        workingDirectory: p.join(tempDir.path, 'pkg'),
        environment: {
          'MIN_COVERAGE': '',
          'PATH': '${stubDir.path}:${Platform.environment['PATH']}',
          'RUNNER_OS_NAME': 'ubuntu-latest',
          'SHARD_INDEX': '0',
          'TOTAL_SHARDS': '1',
        },
      );
      printOnFailure('${result.stdout}${result.stderr}');
      final attempts = File(p.join(stubDir.path, 'attempts'));
      return (
        exitCode: result.exitCode,
        testRuns: attempts.existsSync()
            ? attempts.readAsLinesSync().where((l) => l.isNotEmpty).length
            : 0,
      );
    }

    const droppedConnection =
        'Failed to load "test/example_test.dart": '
        'Connection closed before full header was received';

    for (final site in sites) {
      group(site.name, () {
        test('a dropped suite connection passes on the second run', () async {
          final step = await runStep(site, [
            (output: droppedConnection, exitCode: 1),
            (output: 'All tests passed!', exitCode: 0),
          ]);

          expect(step, (exitCode: 0, testRuns: 2));
        }, testOn: '!windows');

        test('a failing test is not retried and fails the step', () async {
          final step = await runStep(site, [
            (output: 'Some tests failed.', exitCode: 1),
          ]);

          expect(step.exitCode, isNot(0));
          expect(step.testRuns, 1);
        }, testOn: '!windows');

        test('a connection that drops twice fails the step', () async {
          final step = await runStep(site, [
            (output: droppedConnection, exitCode: 1),
          ]);

          expect(step.exitCode, isNot(0));
          expect(step.testRuns, 2);
        }, testOn: '!windows');
      });
    }
  });

  group('the repository-wide shorebird_ci block', () {
    void declare(String block) {
      File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(block, mode: FileMode.append);
    }

    setUp(() {
      createWorkspaceRoot(tempDir, members: ['packages/foo']);
      createPackage(
        tempDir,
        'packages/foo',
        'foo',
        useWorkspace: true,
        addTestDir: true,
      );
    });

    test('required: true emits the aggregator w/o the flag', () async {
      declare('shorebird_ci:\n  required: true\n');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(_readMain(tempDir), contains('\n  required:\n'));
    });

    test('fatal_infos: true emits --fatal-infos w/o the flag', () async {
      declare('shorebird_ci:\n  fatal_infos: true\n');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        contains('dart analyze --fatal-infos .'),
      );
    });

    test('codecov_token_secret threads the token w/o the flag', () async {
      declare('shorebird_ci:\n  codecov_token_secret: CODECOV_TOKEN\n');
      File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        contains(r'token: ${{ secrets.CODECOV_TOKEN }}'),
      );
    });

    test('an empty codecov_token_secret reads as unset', () async {
      declare('shorebird_ci:\n  codecov_token_secret: ""\n');
      File(p.join(tempDir.path, 'codecov.yml')).writeAsStringSync('');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        isNot(contains('secrets.')),
      );
    });

    test('a block that is not a map reads as no configuration', () async {
      declare('shorebird_ci: nope\n');
      initGitRepo(tempDir);

      await runGenerate(tempDir, extra: ['--style', 'static']);

      expect(_readMain(tempDir), isNot(contains('\n  required:\n')));
      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        contains('dart analyze --fatal-warnings .'),
      );
    });

    test('a flag still wins over a block that leaves it out', () async {
      declare('shorebird_ci:\n  required: true\n');
      initGitRepo(tempDir);

      await runGenerate(
        tempDir,
        extra: ['--style', 'static', '--fatal-infos'],
      );

      expect(_readMain(tempDir), contains('\n  required:\n'));
      expect(
        readWorkflow('_shorebird_ci_dart.yaml'),
        contains('dart analyze --fatal-infos .'),
      );
    });
  });
}

String _readMain(Directory repoRoot) {
  return File(
    p.join(repoRoot.path, '.github', 'workflows', 'shorebird_ci.yaml'),
  ).readAsStringSync();
}

/// The `dorny/paths-filter` patterns in a static orchestrator, by slug.
Map<String, List<String>> _readStaticFilters(String yaml) {
  final jobs = (loadYaml(yaml) as YamlMap)['jobs'] as YamlMap;
  final steps = (jobs['changes'] as YamlMap)['steps'] as YamlList;
  final step =
      steps.firstWhere((step) => (step as YamlMap)['id'] == 'filter')
          as YamlMap;
  final filters =
      loadYaml((step['with'] as YamlMap)['filters'] as String) as YamlMap;
  return {
    for (final MapEntry(key: slug, value: paths) in filters.entries)
      slug as String: (paths as YamlList).cast<String>().toList(),
  };
}

String _readAll(Directory dir) => [
  for (final f in dir.listSync().whereType<File>()) f.readAsStringSync(),
].join('\n');

/// Expects every job in every workflow under [repoRoot] to stay at
/// `contents: read`, leaving out jobs named [except]. Returns the jobs, keyed
/// by name.
Map<String, Object?> _expectReadOnlyJobs(Directory repoRoot, {String? except}) {
  final workflows = Directory(p.join(repoRoot.path, '.github', 'workflows'));
  final jobs = <String, Object?>{};
  for (final file in workflows.listSync().whereType<File>()) {
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    jobs.addAll((doc['jobs'] as YamlMap).cast<String, Object?>());
  }
  expect(jobs, isNotEmpty);
  for (final MapEntry(key: name, value: job) in jobs.entries) {
    if (name == except) continue;
    final permissions = (job! as YamlMap)['permissions'];
    if (permissions != null) {
      expect(permissions, {'contents': 'read'}, reason: name);
    }
  }
  return jobs;
}

/// The main workflow cancels a superseded PR run, and only PR runs share a
/// group.
void _expectPrOnlyConcurrency(String yaml) {
  final doc = loadYaml(yaml) as YamlMap;
  final concurrency = doc['concurrency'] as YamlMap;
  expect(
    concurrency['group'],
    [
      r'${{ github.workflow }}',
      r'${{ github.event.pull_request.number || github.run_id }}',
    ].join('-'),
  );
  expect(concurrency['cancel-in-progress'], isTrue);
}
