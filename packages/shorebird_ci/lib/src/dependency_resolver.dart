import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/pubspec.dart';
import 'package:yaml/yaml.dart';

/// Resolves transitive path dependencies for Dart packages in a repository.
///
/// Understands both `path:` dependencies and Dart workspace
/// `resolution: workspace` members.
class DependencyResolver {
  /// Creates a resolver rooted at [repoRoot].
  DependencyResolver(this.repoRoot);

  /// The absolute path to the repository root.
  final String repoRoot;

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

    final deps = <String>[];
    for (final entry in dependencies.entries) {
      if (entry.value is YamlMap) {
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
}
