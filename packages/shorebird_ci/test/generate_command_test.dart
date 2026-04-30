import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/commands.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Runs `generate` via the command runner.
Future<int?> runGenerate(
  Directory repoRoot, {
  List<String> extra = const [],
}) async {
  final runner = CommandRunner<int>('test', 'test')
    ..addCommand(GenerateCommand());
  return runner.run([
    'generate',
    '--repo-root',
    repoRoot.path,
    ...extra,
  ]);
}

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
      expect(yaml, contains('streetsidesoftware/cspell-action'));
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
      expect(yaml, contains('streetsidesoftware/cspell-action'));
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
}

String _readMain(Directory repoRoot) {
  return File(
    p.join(repoRoot.path, '.github', 'workflows', 'shorebird_ci.yaml'),
  ).readAsStringSync();
}
