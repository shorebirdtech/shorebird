import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/pubspec.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:shorebird_ci/src/workspace.dart';
import 'package:yaml/yaml.dart';

/// Resolves transitive path dependencies for Dart packages in a repository.
///
/// Understands both `path:` dependencies and Dart workspace
/// `resolution: workspace` members. A workspace member that depends on
/// another member by name alone (`foo: ^1.0.0`) gets that member, as
/// pub resolves it, not the hosted package.
class DependencyResolver {
  /// Creates a resolver rooted at [repoRoot].
  DependencyResolver(this.repoRoot);

  /// The absolute path to the repository root.
  final String repoRoot;

  /// Workspace member directories (repo-relative), by package name,
  /// keyed by the workspace root's absolute path.
  final _membersByRoot = <String, Map<String, String>>{};

  /// Submodule mount points (repo-relative POSIX paths) from `.gitmodules`.
  late final Set<String> submodulePaths = _readSubmodulePaths(repoRoot);

  static Set<String> _readSubmodulePaths(String repoRoot) {
    final file = File(p.join(repoRoot, '.gitmodules'));
    if (!file.existsSync()) return const {};
    final pattern = RegExp(r'^\s*path\s*=\s*(.+?)\s*$', multiLine: true);
    return {
      for (final match in pattern.allMatches(file.readAsStringSync()))
        p.posix.normalize(match.group(1)!.replaceAll(r'\', '/')),
    };
  }

  /// Whether [repoRelativePath] is a git submodule mount point.
  bool isSubmodule(String repoRelativePath) =>
      submodulePaths.contains(repoRelativePath);

  /// Collapses [repoRelativePath] to its git submodule mount point when it
  /// resides inside a submodule declared in `.gitmodules`.
  ///
  /// `git diff` reports a submodule update as the mount point path itself,
  /// never as a path beneath it.
  String collapseSubmodulePath(String repoRelativePath) {
    for (final submodule in submodulePaths) {
      if (repoRelativePath == submodule ||
          p.posix.isWithin(submodule, repoRelativePath)) {
        return submodule;
      }
    }
    return repoRelativePath;
  }

  /// Returns all transitive path dependency directories (repo-relative)
  /// for the package at [packageDir], collapsing any dependency inside a
  /// git submodule to that submodule's mount point.
  Set<String> resolve(String packageDir) {
    final rawDirs = _resolveRaw(packageDir);
    return {
      for (final dir in rawDirs)
        if (dir == packageDir) dir else collapseSubmodulePath(dir),
    };
  }

  Set<String> _resolveRaw(String packageDir) {
    final visited = <String>{};
    final queue = <String>[packageDir];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!visited.add(current)) continue;

      final deps = _getPathDependencies(current);
      queue.addAll(deps.where((d) => !visited.contains(d)));
    }

    return visited;
  }

  /// Returns extra input paths or globs (repo-relative) declared under
  /// `shorebird_ci: inputs:` or `verify_cache: inputs:` in `pubspec.yaml`
  /// for [packageDir] and its transitive local dependencies.
  Set<String> extraInputs(String packageDir) {
    final inputs = <String>{};
    for (final dir in _resolveRaw(packageDir)) {
      final pubspec = readPubspec(p.join(repoRoot, dir));
      if (pubspec == null) continue;
      for (final section in const ['shorebird_ci', 'verify_cache']) {
        final config = pubspec[section];
        if (config is! YamlMap) continue;
        final rawInputs = config['inputs'];
        if (rawInputs is! YamlList) continue;
        for (final entry in rawInputs) {
          final raw = entry.toString().trim().replaceAll(r'\', '/');
          if (raw.isEmpty) continue;
          final resolved = _resolveInputPath(dir, raw);
          inputs.add(collapseSubmodulePath(resolved));
        }
      }
    }
    return inputs;
  }

  String _resolveInputPath(String packageDir, String raw) {
    if (raw.startsWith('./') || raw.startsWith('../') || packageDir == '.') {
      return p.posix.normalize(p.posix.join(packageDir, raw));
    }
    final probe = raw.replaceFirst(RegExp(r'/\*\*?$'), '');
    final inPackage = p.join(repoRoot, packageDir, probe);
    if (File(inPackage).existsSync() || Directory(inPackage).existsSync()) {
      return p.posix.normalize(p.posix.join(packageDir, raw));
    }
    return p.posix.normalize(raw);
  }

  /// Returns the sorted list of `dorny/paths-filter` patterns for [packageDir],
  /// including transitive dependencies (with submodule mount-point collapse),
  /// workspace files, extra `pubspec.yaml` inputs, and optional [workflowFile].
  List<String> filterPaths(String packageDir, {String? workflowFile}) {
    final paths = <String>{
      for (final dep in resolve(packageDir))
        if (isSubmodule(dep)) dep else '$dep/**',
      ...workspaceFiles(packageDir),
      ...extraInputs(packageDir),
      ?workflowFile,
    };
    return paths.toList()..sort();
  }

  List<String> _getPathDependencies(String packageDir) {
    final pubspec = readPubspec(p.join(repoRoot, packageDir));
    final dependencies = pubspec?['dependencies'] as YamlMap?;
    if (dependencies == null) return const [];

    final members = _workspaceMembers(packageDir);
    final deps = <String>[];
    for (final entry in dependencies.entries) {
      final member = members[entry.key];
      if (member != null) {
        deps.add(member);
      } else if (entry.value is YamlMap) {
        final pathValue = (entry.value as YamlMap)['path'];
        if (pathValue != null) {
          // Repo-relative paths flow into YAML and Linux runners, so
          // resolve with the POSIX context to keep separators forward-
          // slashed on Windows.
          final resolved = p.posix.normalize(
            p.posix.join(packageDir, pathValue as String),
          );
          deps.add(resolved);
        }
      }
    }

    return deps;
  }

  /// Returns the files (repo-relative) outside [packageDir] that decide
  /// what it resolves to: its workspace root's `pubspec.yaml` and
  /// `pubspec.lock`, if it uses `resolution: workspace`. A workspace
  /// member has no lockfile of its own, so a dependency bump changes
  /// only these.
  Set<String> workspaceFiles(String packageDir) {
    final absolute = p.join(repoRoot, packageDir);
    if (!usesWorkspaceResolution(absolute)) return const {};
    final root = findWorkspaceRoot(absolute);
    if (root == null) return const {};
    return {
      for (final file in ['pubspec.yaml', 'pubspec.lock'])
        posixRelative(p.join(root.path, file), from: repoRoot),
    };
  }

  /// Returns the members of the workspace [packageDir] resolves in,
  /// or an empty map if it doesn't use `resolution: workspace`.
  Map<String, String> _workspaceMembers(String packageDir) {
    final absolute = p.join(repoRoot, packageDir);
    if (!usesWorkspaceResolution(absolute)) return const {};
    final root = findWorkspaceRoot(absolute);
    if (root == null) return const {};
    return _membersByRoot.putIfAbsent(root.path, () {
      final workspace = readPubspec(root.path)?['workspace'] as YamlList;
      final members = <String, String>{};
      for (final member in workspace.whereType<String>()) {
        final memberDir = p.join(root.path, member);
        final name = readPubspec(memberDir)?['name'];
        if (name is! String) continue;
        members[name] = posixRelative(memberDir, from: repoRoot);
      }
      return members;
    });
  }
}
