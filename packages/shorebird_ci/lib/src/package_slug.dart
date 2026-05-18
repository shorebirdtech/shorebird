import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';

/// Maps each package to the YAML map key used for its dorny filter,
/// changes-job output, and per-package job in the static main workflow.
///
/// A package's slug defaults to its `name:`. When two or more packages
/// share a `name:`, those packages fall back to `<parent_dir>_<name>`
/// to disambiguate. Parent dirs are normalized to pub's
/// `[a-z][a-z0-9_]*` rules so the slug can be used in GitHub Actions
/// expressions. `generate` writes these slugs and `verify` reads them,
/// so both commands must agree on the rule.
Map<PackageDescription, String> computePackageSlugs({
  required List<PackageDescription> packages,
  required String repoRoot,
}) {
  final byName = <String, List<PackageDescription>>{};
  for (final pkg in packages) {
    byName.putIfAbsent(pkg.name, () => []).add(pkg);
  }
  final duplicateNames = {
    for (final entry in byName.entries)
      if (entry.value.length > 1) entry.key,
  };

  return {
    for (final pkg in packages)
      pkg: _slugFor(
        package: pkg,
        repoRoot: repoRoot,
        duplicateNames: duplicateNames,
      ),
  };
}

String _slugFor({
  required PackageDescription package,
  required String repoRoot,
  required Set<String> duplicateNames,
}) {
  if (!duplicateNames.contains(package.name)) return package.name;
  final relative = posixRelative(package.rootPath, from: repoRoot);
  final parts = relative.split('/');
  if (parts.length < 2) return package.name;
  final parent = parts[parts.length - 2].toLowerCase().replaceAll(
    RegExp('[^a-z0-9_]'),
    '_',
  );
  return '${parent}_${package.name}';
}
