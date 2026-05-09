import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/codecov.dart';
import 'package:shorebird_ci/src/cspell.dart';
import 'package:shorebird_ci/src/git.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/pubspec.dart';
import 'package:shorebird_ci/src/repository_description.dart';
import 'package:shorebird_ci/src/workspace.dart' as workspace;
import 'package:yaml/yaml.dart';

/// Analyzes a repository to discover its Dart packages and structure.
class RepositoryAnalyzer {
  /// Creates a [RepositoryAnalyzer].
  RepositoryAnalyzer({Git? git}) : _git = git ?? const Git();

  final Git _git;

  /// Generates a [RepositoryDescription] for the given [repositoryRoot].
  RepositoryDescription analyze({required Directory repositoryRoot}) {
    if (!repositoryRoot.existsSync()) {
      throw FileSystemException(
        'Repository root does not exist',
        repositoryRoot.path,
      );
    }

    final submodulePaths = _git.submodulePaths(
      workingDirectory: repositoryRoot.path,
    );
    final absoluteSubmodulePaths = submodulePaths
        .map((e) => p.join(repositoryRoot.path, e))
        .toSet();

    // One walk of the repo, pruning into submodules and nested git
    // repos/worktrees. Collects pubspecs, codecov configs, and cspell
    // configs in a single pass.
    final pubspecFiles = <File>[];
    var hasCodecov = false;
    File? cSpellConfigFile;

    walkPruned(
      root: repositoryRoot,
      shouldPruneDirectory: (dir) =>
          _isUnderSubmodule(dir.path, absoluteSubmodulePaths) ||
          _hasNestedGit(dir),
      onFile: (entry) {
        if (entry.path.endsWith('pubspec.yaml')) {
          pubspecFiles.add(entry);
        }

        final relPath = p.relative(
          entry.path,
          from: repositoryRoot.path,
        );
        if (!hasCodecov && codecovFileNames.contains(relPath)) {
          hasCodecov = true;
        }
        if (cSpellConfigFile == null &&
            cSpellConfigFileNames.contains(relPath)) {
          cSpellConfigFile = entry;
        }
      },
    );

    final packages = _filterPackages(
      pubspecFiles: pubspecFiles,
      repositoryRoot: repositoryRoot,
    );

    final packageDescriptions = packages
        .map((pubspec) {
          final name = packageName(root: pubspec.parent);
          if (name == null) return null;
          _requireSafePackageName(name, source: pubspec.path);
          final relative = posixRelative(
            pubspec.parent.path,
            from: repositoryRoot.path,
          );
          _requireSafePath(relative);
          return PackageDescription(
            name: name,
            rootPath: pubspec.parent.path,
          );
        })
        .whereType<PackageDescription>()
        .toList();

    _checkForDuplicateNames(packageDescriptions);

    return RepositoryDescription(
      packages: packageDescriptions,
      root: repositoryRoot,
      hasCodecov: hasCodecov,
      cspellConfig: cSpellConfigFile,
    );
  }

  static void _checkForDuplicateNames(
    List<PackageDescription> packages,
  ) {
    final byName = <String, List<PackageDescription>>{};
    for (final pkg in packages) {
      byName.putIfAbsent(pkg.name, () => []).add(pkg);
    }
    final duplicates = byName.entries.where((e) => e.value.length > 1);
    if (duplicates.isEmpty) return;

    final buffer = StringBuffer(
      'Duplicate package names found. Each package in the workspace '
      'must have a unique `name:` in its pubspec.yaml.\n',
    );
    for (final entry in duplicates) {
      buffer.writeln('  ${entry.key}:');
      for (final pkg in entry.value) {
        buffer.writeln('    - ${pkg.rootPath}');
      }
    }
    throw StateError(buffer.toString().trimRight());
  }

  /// Allowed characters in a package or subpackage path: letters,
  /// digits, `_`, `-`, `.`, and `/`. Any other character (whitespace,
  /// shell metacharacters, Unicode) is rejected.
  ///
  /// The generated workflow word-splits matrix entries via
  /// `for sub in ${{ matrix.subpackages }}; do ... done` — a path with
  /// shell metacharacters would otherwise be injected directly into
  /// the runner's shell. Restricting paths to a portable POSIX subset
  /// makes the simple loop safe by construction.
  static final _safePathRegex = RegExp(r'^[A-Za-z0-9._/-]+$');

  static void _requireSafePath(String path) {
    if (_safePathRegex.hasMatch(path)) return;
    throw FormatException(
      'shorebird_ci requires package paths to be portable POSIX paths '
      'using only letters, digits, `_`, `-`, `.`, and `/`. The '
      'generated CI workflow embeds these paths in shell commands and '
      'cannot tolerate whitespace, shell metacharacters, or Unicode. '
      'Got: $path',
    );
  }

  /// Pub's own naming convention for packages: lowercase letter or
  /// underscore start, then lowercase letters, digits, and underscores.
  /// `pubspec.yaml` is just YAML — pub doesn't gate this name until you
  /// publish — so a malformed name can land here and get embedded as
  /// a YAML map key in the generated workflow. Validate at analysis
  /// time instead.
  static final _safePackageNameRegex = RegExp(r'^[a-z][a-z0-9_]*$');

  static void _requireSafePackageName(String name, {required String source}) {
    if (_safePackageNameRegex.hasMatch(name)) return;
    throw FormatException(
      'Invalid package name in $source: "$name". Package names must '
      'start with a lowercase letter and contain only lowercase '
      'letters, digits, and underscores '
      '(see https://dart.dev/tools/pub/pubspec#name).',
    );
  }

  static bool _isUnderSubmodule(String path, Set<String> submodulePaths) {
    for (final submodule in submodulePaths) {
      // p.equals / p.isWithin handle mixed separators (the submodule
      // path comes from git as POSIX, while the walked Directory.path
      // is platform-native — naive string compare misses on Windows).
      // p.isWithin is also non-trivial-prefix-aware: a submodule at
      // `packages/foo` does not match `packages/foo_bar`.
      if (p.equals(path, submodule)) return true;
      if (p.isWithin(submodule, path)) return true;
    }
    return false;
  }

  static bool _hasNestedGit(Directory dir) {
    // Nested git repos and worktrees both have a `.git` entry at their
    // root: a directory for standalone repos, a file for worktrees.
    final gitPath = p.join(dir.path, '.git');
    return File(gitPath).existsSync() || Directory(gitPath).existsSync();
  }

  /// Identifies the packages affected by changes between [baseRef] and
  /// [headRef], including transitive dependents.
  Set<PackageDescription> affectedPackages({
    required RepositoryDescription repository,
    required String baseRef,
    required String headRef,
  }) {
    final changedFiles = _git.changedFiles(
      base: baseRef,
      head: headRef,
      workingDirectory: repository.root.path,
    );

    final packages = repository.packages;
    final directlyChanged = packages
        .where(
          (package) => changedFiles.any(
            (file) => package.containsPath(
              p.normalize(p.join(repository.root.path, file)),
            ),
          ),
        )
        .toSet();

    final targets = {...directlyChanged};
    for (final package in packages) {
      final deps = _recursivePackageDependencies(
        repository: repository,
        package: package,
      );
      if (deps.intersection(directlyChanged).isNotEmpty) {
        targets.add(package);
      }
    }

    return targets;
  }

  List<File> _filterPackages({
    required List<File> pubspecFiles,
    required Directory repositoryRoot,
  }) {
    final packages = <File>[];
    for (final pubspec in pubspecFiles) {
      try {
        if (_git.isIgnored(
          path: pubspec.path,
          workingDirectory: repositoryRoot.path,
        )) {
          continue;
        }
      } on ProcessException {
        continue;
      }

      if (workspace.isWorkspaceStubRoot(pubspec.parent.path)) continue;

      packages.add(pubspec);
    }

    return packages;
  }

  /// The name of the package at the given [root].
  static String? packageName({required Directory root}) {
    return readPubspec(root.path)?['name'] as String?;
  }

  /// Whether the package at the given [root] is a Flutter package.
  static bool isFlutterPackage({required Directory root}) {
    final pubspec = readPubspec(root.path);
    if (pubspec == null) return false;
    final dependencies = pubspec['dependencies'] as YamlMap?;
    final flutter = dependencies?['flutter'] as YamlMap?;
    return flutter != null &&
        flutter.containsKey('sdk') &&
        flutter['sdk'] == 'flutter';
  }

  /// Whether the package at the given [root] depends on Flutter.
  static bool dependsOnFlutter({required Directory root}) {
    if (isFlutterPackage(root: root)) return true;

    final pubspec = readPubspec(root.path);
    if (pubspec == null) return false;
    final environment = pubspec['environment'] as YamlMap?;
    if (environment != null && environment.containsKey('flutter')) {
      return true;
    }

    if (workspace.usesWorkspaceResolution(root.path)) {
      final workspaceRoot = workspace.findWorkspaceRoot(root.path);
      if (workspaceRoot == null) return true;
      // Defensive: a pubspec that declares both `workspace:` and
      // `resolution: workspace` would resolve to itself and recurse
      // forever. Already checked the local pubspec above, so return.
      if (workspaceRoot.path == root.path) return false;
      return dependsOnFlutter(root: workspaceRoot);
    }

    return false;
  }

  /// Whether the package at the given [root] depends on `bloc_lint`.
  static bool dependsOnBlocLint({required Directory root}) {
    final pubspec = readPubspec(root.path);
    if (pubspec == null) return false;
    final devDependencies = pubspec['dev_dependencies'] as YamlMap?;
    return devDependencies?.containsKey('bloc_lint') ?? false;
  }

  /// Whether a package has unit tests.
  static bool hasUnitTests({required Directory root}) {
    return _hasAnyFile(Directory(p.join(root.path, 'test')));
  }

  /// Whether a package has integration tests (Flutter only).
  static bool hasIntegrationTests({required Directory root}) {
    if (!isFlutterPackage(root: root)) return false;
    return _hasAnyFile(Directory(p.join(root.path, 'integration_test')));
  }

  static bool _hasAnyFile(Directory dir) {
    if (!dir.existsSync()) return false;
    var found = false;
    walkPruned(
      root: dir,
      shouldPruneDirectory: _hasNestedGit,
      onFile: (_) => found = true,
    );
    return found;
  }

  /// Packages nested within [package]'s directory structure.
  ///
  /// Skips nested git repos and worktrees so that vendored packages,
  /// build outputs containing pubspec.yaml, and Claude Code worktrees
  /// don't appear as subpackages.
  ///
  /// Each subpackage's relative path is validated to be shell-safe
  /// (see [_requireSafePath]); a path outside `[A-Za-z0-9._/-]+` is
  /// a generation-time error rather than a CI-time injection.
  static Iterable<PackageDescription> subpackages({
    required PackageDescription package,
  }) {
    final found = <PackageDescription>[];
    walkPruned(
      root: package.root,
      // Skip the parent package's own pubspec; only return descendants.
      shouldPruneDirectory: (dir) =>
          dir.path != package.rootPath && _hasNestedGit(dir),
      onFile: (file) {
        if (!file.path.endsWith('pubspec.yaml')) return;
        if (p.equals(file.parent.path, package.rootPath)) return;
        final name = packageName(root: file.parent);
        if (name == null) return;
        final relative = posixRelative(
          file.parent.path,
          from: package.rootPath,
        );
        _requireSafePath(relative);
        found.add(
          PackageDescription(name: name, rootPath: file.parent.path),
        );
      },
    );
    return found;
  }

  static Set<PackageDescription> _recursivePackageDependencies({
    required RepositoryDescription repository,
    required PackageDescription package,
  }) {
    final ret = <PackageDescription>{};
    final toVisit = {package};
    while (toVisit.isNotEmpty) {
      final current = toVisit.first;
      toVisit.remove(current);
      final dependencies = _localDependencies(
        repository: repository,
        package: current,
      );
      final newDependencies = dependencies.difference(ret);
      ret.addAll(newDependencies);
      toVisit.addAll(newDependencies);
    }
    return ret;
  }

  static Set<PackageDescription> _localDependencies({
    required RepositoryDescription repository,
    required PackageDescription package,
  }) {
    final pubspec = readPubspec(package.root.path);
    if (pubspec == null) return {};
    final usesWorkspace = pubspec['resolution'] == 'workspace';
    final dependencies = pubspec['dependencies'] as YamlMap?;
    if (dependencies == null) return {};

    return dependencies.entries
        .map((entry) {
          // Workspace packages can reference local deps by name alone.
          if (usesWorkspace) {
            final byName = repository.packages
                .where((p) => p.name == entry.key)
                .firstOrNull;
            if (byName != null) return byName;
          }
          if (entry.value is! YamlMap) return null;
          final depPath = (entry.value as YamlMap)['path'] as String?;
          if (depPath == null) return null;
          final normalizedPath = p.canonicalize(
            p.join(package.root.path, depPath),
          );
          return repository.packages
              .where(
                (pkg) => p.canonicalize(pkg.root.path) == normalizedPath,
              )
              .firstOrNull;
        })
        .whereType<PackageDescription>()
        .toSet();
  }
}

/// Walks the directory tree rooted at [root], invoking [onFile] for
/// every regular file. Directories for which [shouldPruneDirectory]
/// returns true are not descended into. Symbolic links are not followed.
void walkPruned({
  required Directory root,
  required bool Function(Directory dir) shouldPruneDirectory,
  required void Function(File file) onFile,
}) {
  void visit(Directory dir) {
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is Directory) {
        if (shouldPruneDirectory(entry)) continue;
        visit(entry);
      } else if (entry is File) {
        onFile(entry);
      }
    }
  }

  visit(root);
}

/// Like [p.relative], but always returns a POSIX-style path with
/// forward-slash separators. Use at every boundary where a relative
/// path leaves Dart for YAML, shell, or a Linux runner — `p.relative`
/// emits `\` on Windows, which would land in the generated workflow as
/// a path that the runner can't resolve.
String posixRelative(String path, {required String from}) {
  return p.relative(path, from: from).replaceAll(r'\', '/');
}
