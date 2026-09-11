import 'dart:io';

import 'package:shorebird_ci/src/flutter_version_resolver.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';

/// Computes the list of package metadata maps consumed by the dynamic
/// CI workflow's `matrix.include`.
///
/// Each entry has the shape documented on `AffectedPackagesCommand`.
/// [sdkFilter] may be `'dart'`, `'flutter'`, or `null` (no filter).
List<Map<String, Object?>> affectedPackagesMetadata({
  required Directory repoRoot,
  String? baseRef,
  String? headRef,
  String? sdkFilter,
  bool all = false,
  RepositoryAnalyzer? analyzer,
}) {
  final a = analyzer ?? RepositoryAnalyzer();
  final repository = a.analyze(repositoryRoot: repoRoot);
  if (repository.packages.isEmpty) return const [];

  var packages = all
      ? repository.packages
      : a
            .affectedPackages(
              repository: repository,
              baseRef: baseRef ?? 'origin/main',
              headRef: headRef ?? 'HEAD',
            )
            .toList();

  if (sdkFilter != null) {
    packages = packages.where((pkg) {
      final isFlutter = RepositoryAnalyzer.dependsOnFlutter(root: pkg.root);
      return sdkFilter == 'flutter' ? isFlutter : !isFlutter;
    }).toList();
  }

  final sorted = packages.toList()..sort((a, b) => a.name.compareTo(b.name));

  return sorted.map((pkg) {
    final isFlutter = RepositoryAnalyzer.dependsOnFlutter(root: pkg.root);
    final subpackages =
        RepositoryAnalyzer.subpackages(package: pkg)
            .map((sub) => posixRelative(sub.rootPath, from: pkg.rootPath))
            .toList()
          ..sort();

    return {
      'name': pkg.name,
      'path': posixRelative(pkg.rootPath, from: repoRoot.path),
      'sdk': isFlutter ? 'flutter' : 'dart',
      'flutter_version': isFlutter
          ? (resolveFlutterVersion(packagePath: pkg.rootPath) ?? '')
          : '',
      'has_bloc_lint': RepositoryAnalyzer.dependsOnBlocLint(root: pkg.root),
      'has_integration_tests': RepositoryAnalyzer.hasIntegrationTests(
        root: pkg.root,
      ),
      // Space-separated so the matrix job can iterate with a shell for
      // loop. Safe because RepositoryAnalyzer rejects any package path
      // containing shell metacharacters; see _requireSafePath there.
      'subpackages': subpackages.join(' '),
    };
  }).toList();
}
