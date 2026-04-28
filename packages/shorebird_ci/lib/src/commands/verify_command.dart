import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/dorny_filter.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';

/// Marker comment that the `generate` command writes into dynamic
/// workflows. Verify uses this to detect dynamic coverage instead of
/// substring-searching for the call (which falsely matches comments,
/// `run: echo "..."`, and similar).
const dynamicCoverageMarker = '# shorebird_ci-managed: dynamic';

/// Verifies that every discovered package has CI coverage somewhere in
/// `.github/workflows/`.
///
/// Coverage can be provided in two ways:
///   - **Dynamic**: a workflow that calls `shorebird_ci affected_packages`
///     covers every package automatically. One dynamic workflow means no
///     missing packages.
///   - **Static**: each package name appears in a `dorny/paths-filter`
///     block somewhere. Missing packages are reported with the dorny
///     entry that should be added (including transitive deps).
class VerifyCommand extends Command<int> with RepoRootOption {
  /// Creates a [VerifyCommand].
  VerifyCommand() {
    addRepoRootOption();
    argParser.addOption(
      'ignore',
      help: 'Comma-separated list of package names to ignore.',
    );
  }

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify every package has CI coverage';

  @override
  Future<int> run() async {
    final ignoreStr = argResults!['ignore'] as String?;
    final ignoreSet = ignoreStr != null
        ? ignoreStr.split(',').map((s) => s.trim()).toSet()
        : <String>{};

    final analyzer = RepositoryAnalyzer();
    final repository = analyzer.analyze(
      repositoryRoot: Directory(repoRoot),
    );

    final workflowDir = Directory(
      p.join(repoRoot, '.github', 'workflows'),
    );
    if (!workflowDir.existsSync()) {
      stderr.writeln('No .github/workflows directory found.');
      return 1;
    }

    // Map each package name to the workflow(s) that cover it.
    final coverageMap = <String, List<String>>{};
    final workflowFiles =
        workflowDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final dynamicWorkflows = <String>[];

    for (final file in workflowFiles) {
      final content = file.readAsStringSync();
      final fileName = p.basename(file.path);

      if (_usesDynamicCoverage(content)) {
        dynamicWorkflows.add(fileName);
        continue;
      }

      final names = extractDornyFilterNames(content);
      for (final name in names) {
        coverageMap.putIfAbsent(name, () => []).add(fileName);
      }
    }

    final allPackages = repository.packages.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (dynamicWorkflows.isNotEmpty) {
      stdout.writeln(
        'Using dynamic coverage via ${dynamicWorkflows.join(', ')} — '
        'all ${allPackages.length} packages covered at runtime.',
      );
      return 0;
    }

    final missing = <PackageDescription>[];

    for (final pkg in allPackages) {
      if (ignoreSet.contains(pkg.name)) continue;
      final workflows = coverageMap[pkg.name];
      if (workflows != null) {
        stdout.writeln(
          'OK: ${pkg.name} (${workflows.join(', ')})',
        );
      } else {
        missing.add(pkg);
      }
    }

    if (missing.isEmpty) {
      stdout.writeln('\nAll packages have CI coverage.');
      return 0;
    }

    stdout.writeln();
    final resolver = DependencyResolver(repoRoot);

    for (final pkg in missing) {
      final packageDir = p.relative(pkg.rootPath, from: repoRoot);
      final deps = resolver.resolve(packageDir);
      final sortedDeps = deps.toList()..sort();

      stdout
        ..writeln('MISSING: ${pkg.name}')
        ..writeln('  Add this entry to a dorny paths-filter block:')
        ..writeln('            ${pkg.name}:');
      for (final dep in sortedDeps) {
        stdout.writeln('              - $dep/**');
      }
      stdout.writeln();
    }

    stderr.writeln(
      '${missing.length} package(s) missing from CI coverage.',
    );
    return 1;
  }

  /// Whether a workflow uses the dynamic affected_packages approach.
  ///
  /// Looks for the marker comment that the `generate` command writes.
  /// Substring-searching for `shorebird_ci affected_packages` would
  /// also match YAML comments, commented-out code, and `run: echo ...`
  /// strings — the marker is unambiguous.
  ///
  /// The marker is plain text (a YAML comment), so editing the file
  /// keeps the marker in place by default. A user who removes the
  /// marker without also removing the dynamic call loses coverage and
  /// `verify` fails — which is the right failure mode.
  bool _usesDynamicCoverage(String workflowContent) {
    return workflowContent.contains(dynamicCoverageMarker);
  }
}
