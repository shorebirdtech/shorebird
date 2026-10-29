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

  /// Returns all transitive path dependency directories (repo-relative)
  /// for the package at [packageDir].
  Set<String> resolve(String packageDir) {
    final visited = <String>{};
    final queue = <String>[packageDir];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      final deps = _getPathDependencies(current);
      queue.addAll(deps.where((d) => !visited.contains(d)));
    }

    return visited;
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
