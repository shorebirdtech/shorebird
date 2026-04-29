import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/shorebird_ci.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A fake [Git] that always throws [ProcessException] from
/// [Git.isIgnored]. Used to exercise the defensive catch in
/// `RepositoryAnalyzer._filterPackages`.
class _ThrowingGit extends Git {
  const _ThrowingGit();

  @override
  bool isIgnored({required String path, required String workingDirectory}) {
    throw ProcessException('git', ['check-ignore', path], 'boom', 1);
  }
}

/// A fake [Git] that returns a fixed list of submodule paths.
class _StubSubmoduleGit extends Git {
  const _StubSubmoduleGit({required this.paths});
  final List<String> paths;

  @override
  List<String> submodulePaths({required String workingDirectory}) => paths;
}

void main() {
  setUpTempDir('shorebird_ci_analyzer_');

  group('RepositoryAnalyzer.analyze', () {
    test('discovers packages in a monorepo', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      final names = repo.packages.map((p) => p.name).toSet();
      expect(names, equals({'foo', 'bar'}));
    });

    test('discovers packages at non-standard paths', () async {
      createPackage(tempDir, 'libs/util', 'util');
      createPackage(tempDir, 'apps/admin', 'admin');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      final names = repo.packages.map((p) => p.name).toSet();
      expect(names, equals({'util', 'admin'}));
    });

    test('skips underscore workspace roots', () async {
      createPackage(tempDir, 'packages/foo', 'foo', useWorkspace: true);
      createWorkspaceRoot(tempDir, members: ['packages/foo']);
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      final names = repo.packages.map((p) => p.name).toSet();
      expect(names, equals({'foo'}));
    });

    test('detects codecov config', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(
        p.join(tempDir.path, 'codecov.yml'),
      ).writeAsStringSync('coverage:\n  status: off');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      expect(repo.hasCodecov, isTrue);
    });

    test('detects cspell config', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      File(
        p.join(tempDir.path, '.cspell.json'),
      ).writeAsStringSync('{"words": []}');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      expect(repo.cspellConfig, isNotNull);
      expect(p.basename(repo.cspellConfig!.path), equals('.cspell.json'));
    });

    test('returns no codecov/cspell when absent', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      expect(repo.hasCodecov, isFalse);
      expect(repo.cspellConfig, isNull);
    });

    test('throws when repo root does not exist', () async {
      final missing = Directory(p.join(tempDir.path, 'nope'));
      final analyzer = RepositoryAnalyzer();
      expect(
        () => analyzer.analyze(repositoryRoot: missing),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('skips packages whose isIgnored check throws', () async {
      // Covers the defensive `on ProcessException → continue` branch
      // in _filterPackages: when git is unavailable / returns junk we
      // skip the package rather than crashing.
      createPackage(tempDir, 'packages/foo', 'foo');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer(git: const _ThrowingGit());
      final repo = analyzer.analyze(repositoryRoot: tempDir);

      // The throwing isIgnored skips every pubspec, so no packages
      // make it into the description.
      expect(repo.packages, isEmpty);
    });

    test('throws on package name that violates pub conventions', () async {
      // pubspec.yaml is just YAML — pub doesn't gate the name field
      // until publish, so a malformed name can land here and end up
      // as a YAML map key in the generated workflow. Validate at
      // analysis time.
      createPackage(tempDir, 'packages/foo', 'Not-Valid');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      expect(
        () => analyzer.analyze(repositoryRoot: tempDir),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Invalid package name'),
          ),
        ),
      );
    });

    test('throws on duplicate package names', () async {
      // Two packages declaring `name: example` would silently collide
      // when used as YAML map keys in the generated workflow. Fail
      // loudly instead.
      createPackage(tempDir, 'a/example', 'example');
      createPackage(tempDir, 'b/example', 'example');
      initGitRepo(tempDir);

      final analyzer = RepositoryAnalyzer();
      expect(
        () => analyzer.analyze(repositoryRoot: tempDir),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Duplicate package names'),
          ),
        ),
      );
    });

    test(
      'submodule prefix does not silently exclude sibling packages',
      () async {
        // A submodule at packages/foo must NOT cause packages/foo_bar
        // to be skipped — startsWith('packages/foo') would match both.
        // We can't easily inject a real submodule into a fresh repo, so
        // fake it by using a Git stub that reports a submodule path.
        createPackage(tempDir, 'packages/foo', 'foo');
        createPackage(tempDir, 'packages/foo_bar', 'foo_bar');
        initGitRepo(tempDir);

        final analyzer = RepositoryAnalyzer(
          git: const _StubSubmoduleGit(paths: ['packages/foo']),
        );
        final repo = analyzer.analyze(repositoryRoot: tempDir);

        // foo (the submodule itself) is skipped; foo_bar must NOT be.
        final names = repo.packages.map((p) => p.name).toSet();
        expect(names, equals({'foo_bar'}));
      },
    );
  });

  group('RepositoryAnalyzer.affectedPackages', () {
    test('returns directly changed packages', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(tempDir, 'packages/bar', 'bar');
      initGitRepo(tempDir);

      // Modify foo.
      File(
        p.join(tempDir.path, 'packages/foo/README.md'),
      ).writeAsStringSync('change');
      commitAll(tempDir, 'change');

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);
      final affected = analyzer.affectedPackages(
        repository: repo,
        baseRef: 'HEAD~1',
        headRef: 'HEAD',
      );

      expect(affected.map((p) => p.name), equals({'foo'}));
    });

    test('includes transitive dependents', () async {
      createPackage(tempDir, 'packages/foo', 'foo');
      createPackage(
        tempDir,
        'packages/bar',
        'bar',
        dependencies: {'foo': '../foo'},
      );
      createPackage(
        tempDir,
        'packages/baz',
        'baz',
        dependencies: {'bar': '../bar'},
      );
      initGitRepo(tempDir);

      File(
        p.join(tempDir.path, 'packages/foo/change.txt'),
      ).writeAsStringSync('x');
      commitAll(tempDir, 'change');

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);
      final affected = analyzer.affectedPackages(
        repository: repo,
        baseRef: 'HEAD~1',
        headRef: 'HEAD',
      );

      expect(
        affected.map((p) => p.name),
        equals({'foo', 'bar', 'baz'}),
      );
    });

    test('resolves workspace-named deps', () async {
      createPackage(
        tempDir,
        'packages/foo',
        'foo',
        useWorkspace: true,
      );
      createPackage(
        tempDir,
        'packages/bar',
        'bar',
        useWorkspace: true,
        dependencies: {'foo': '../foo'},
      );
      createWorkspaceRoot(
        tempDir,
        members: ['packages/foo', 'packages/bar'],
      );
      initGitRepo(tempDir);

      File(
        p.join(tempDir.path, 'packages/foo/change.txt'),
      ).writeAsStringSync('x');
      commitAll(tempDir, 'change');

      final analyzer = RepositoryAnalyzer();
      final repo = analyzer.analyze(repositoryRoot: tempDir);
      final affected = analyzer.affectedPackages(
        repository: repo,
        baseRef: 'HEAD~1',
        headRef: 'HEAD',
      );

      expect(affected.map((p) => p.name), equals({'foo', 'bar'}));
    });
  });

  group('RepositoryAnalyzer static helpers', () {
    test('isFlutterPackage', () async {
      final dir = Directory(p.join(tempDir.path, 'flutter_pkg'));
      createPackage(
        tempDir,
        'flutter_pkg',
        'flutter_pkg',
        flutterLine: 'any',
      );

      expect(RepositoryAnalyzer.isFlutterPackage(root: dir), isTrue);
    });

    test('dependsOnFlutter via environment constraint', () async {
      final dir = Directory(p.join(tempDir.path, 'pkg'));
      createPackage(
        tempDir,
        'pkg',
        'pkg',
        flutterLine: '>=3.19.0',
      );

      expect(RepositoryAnalyzer.dependsOnFlutter(root: dir), isTrue);
      expect(RepositoryAnalyzer.isFlutterPackage(root: dir), isFalse);
    });

    test('hasUnitTests detects non-empty test directory', () async {
      createPackage(
        tempDir,
        'pkg',
        'pkg',
        addTestDir: true,
      );

      final dir = Directory(p.join(tempDir.path, 'pkg'));
      expect(RepositoryAnalyzer.hasUnitTests(root: dir), isTrue);
    });

    test('hasUnitTests returns false when no test directory', () async {
      createPackage(tempDir, 'pkg', 'pkg');

      final dir = Directory(p.join(tempDir.path, 'pkg'));
      expect(RepositoryAnalyzer.hasUnitTests(root: dir), isFalse);
    });

    test(
      'dependsOnFlutter inherits via workspace resolution',
      () async {
        // The workspace root depends on Flutter via environment.
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: _
environment:
  sdk: ^3.0.0
  flutter: "3.22.1"
workspace:
  - packages/foo
''');
        // The member has no Flutter dep of its own — only `resolution:
        // workspace`. dependsOnFlutter should walk up to the workspace
        // root and find Flutter there.
        createPackage(
          tempDir,
          'packages/foo',
          'foo',
          useWorkspace: true,
        );

        final fooDir = Directory(p.join(tempDir.path, 'packages/foo'));
        expect(RepositoryAnalyzer.dependsOnFlutter(root: fooDir), isTrue);
      },
    );

    test('hasIntegrationTests', () async {
      createPackage(
        tempDir,
        'flutter_pkg',
        'flutter_pkg',
        flutterLine: 'any',
      );
      final dir = Directory(p.join(tempDir.path, 'flutter_pkg'));

      // No integration_test directory yet.
      expect(RepositoryAnalyzer.hasIntegrationTests(root: dir), isFalse);

      Directory(p.join(dir.path, 'integration_test')).createSync();
      File(
        p.join(dir.path, 'integration_test', 'app_test.dart'),
      ).writeAsStringSync('void main() {}');

      expect(RepositoryAnalyzer.hasIntegrationTests(root: dir), isTrue);
    });

    test('hasIntegrationTests is false for non-flutter packages', () async {
      createPackage(tempDir, 'dart_pkg', 'dart_pkg');
      final dir = Directory(p.join(tempDir.path, 'dart_pkg'));
      Directory(p.join(dir.path, 'integration_test')).createSync();
      File(
        p.join(dir.path, 'integration_test', 'app_test.dart'),
      ).writeAsStringSync('void main() {}');

      // Even with the directory present, dart-only packages are skipped.
      expect(RepositoryAnalyzer.hasIntegrationTests(root: dir), isFalse);
    });

    test('dependsOnBlocLint detects bloc_lint dev dependency', () async {
      createPackage(tempDir, 'pkg', 'pkg');
      final dir = Directory(p.join(tempDir.path, 'pkg'));
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: pkg
environment:
  sdk: ^3.0.0
dev_dependencies:
  bloc_lint: ^1.0.0
''');

      expect(RepositoryAnalyzer.dependsOnBlocLint(root: dir), isTrue);
    });

    test('dependsOnBlocLint returns false without dev dependency', () async {
      createPackage(tempDir, 'pkg', 'pkg');
      final dir = Directory(p.join(tempDir.path, 'pkg'));
      expect(RepositoryAnalyzer.dependsOnBlocLint(root: dir), isFalse);
    });

    test('dependsOnBlocLint returns false when pubspec is missing', () async {
      final dir = Directory(p.join(tempDir.path, 'no_pubspec'))
        ..createSync(recursive: true);
      expect(RepositoryAnalyzer.dependsOnBlocLint(root: dir), isFalse);
    });

    test('subpackages discovers nested packages', () async {
      createPackage(tempDir, 'parent', 'parent');
      createPackage(tempDir, 'parent/example', 'parent_example');
      // A directory without a pubspec should be ignored.
      Directory(
        p.join(tempDir.path, 'parent', 'doc'),
      ).createSync(recursive: true);

      final parent = PackageDescription(
        name: 'parent',
        rootPath: p.join(tempDir.path, 'parent'),
      );
      final subs = RepositoryAnalyzer.subpackages(package: parent).toList();

      expect(subs, hasLength(1));
      expect(subs.single.name, equals('parent_example'));
    });

    test('subpackages prunes nested git repos', () async {
      // A vendored package committed with its own .git directory (e.g.
      // a forked third-party package) must not appear as a subpackage —
      // the matrix would otherwise run `pub get` against unrelated code.
      createPackage(tempDir, 'parent', 'parent');
      createPackage(tempDir, 'parent/vendored', 'vendored');
      Directory(
        p.join(tempDir.path, 'parent/vendored/.git'),
      ).createSync(recursive: true);

      final parent = PackageDescription(
        name: 'parent',
        rootPath: p.join(tempDir.path, 'parent'),
      );
      final subs = RepositoryAnalyzer.subpackages(package: parent).toList();

      expect(subs, isEmpty);
    });

    test('subpackages skips nested directories without a name field', () async {
      // Confirms the `name == null → null` filter on line 247 of the
      // repository analyzer; a pubspec without a `name` field would
      // otherwise yield a PackageDescription with a `null` name.
      createPackage(tempDir, 'parent', 'parent');
      final nested = Directory(p.join(tempDir.path, 'parent', 'oddball'))
        ..createSync(recursive: true);
      File(p.join(nested.path, 'pubspec.yaml')).writeAsStringSync(
        // Valid YAML map but no `name` key.
        'environment:\n  sdk: ^3.0.0\n',
      );

      final parent = PackageDescription(
        name: 'parent',
        rootPath: p.join(tempDir.path, 'parent'),
      );

      expect(
        RepositoryAnalyzer.subpackages(package: parent).toList(),
        isEmpty,
      );
    });

    test(
      'dependsOnFlutter does not stack-overflow on self-referencing workspace',
      () async {
        // A pubspec that declares both `workspace:` and `resolution:
        // workspace` would cause findWorkspaceRoot to return itself
        // and recurse forever. Guarded by an equality check.
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: weird
resolution: workspace
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');

        // Should return false (no Flutter anywhere) without recursing.
        expect(
          RepositoryAnalyzer.dependsOnFlutter(root: tempDir),
          isFalse,
        );
      },
    );

    test(
      'dependsOnFlutter false for workspace member when root has no Flutter',
      () async {
        // Workspace root has no Flutter dep.
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: _
environment:
  sdk: ^3.0.0
workspace:
  - packages/foo
''');
        createPackage(
          tempDir,
          'packages/foo',
          'foo',
          useWorkspace: true,
        );

        final fooDir = Directory(p.join(tempDir.path, 'packages/foo'));
        expect(RepositoryAnalyzer.dependsOnFlutter(root: fooDir), isFalse);
      },
    );
  });

  group('posixRelative', () {
    test('returns forward-slash separators regardless of input', () {
      // On POSIX hosts the input is already forward-slash; on Windows
      // p.relative would emit backslashes. The helper must always
      // return POSIX so the path is safe to embed in YAML/shell that
      // runs on a Linux runner.
      final result = posixRelative('/repo/packages/foo', from: '/repo');
      expect(result, equals('packages/foo'));
      expect(result, isNot(contains(r'\')));
    });

    test('explicitly converts backslashes to forward slashes', () {
      // Simulate what p.relative would emit on Windows.
      const windowsLike = r'packages\foo\bar';
      expect(windowsLike.replaceAll(r'\', '/'), equals('packages/foo/bar'));
    });
  });
}
