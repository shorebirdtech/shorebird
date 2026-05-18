import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/dorny_filter.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/package_slug.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:yaml/yaml.dart';

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
///   - **Static**: each package's slug (see [computePackageSlugs]) appears
///     in a `dorny/paths-filter` block somewhere. For most packages the
///     slug is just the package name; when two packages share a name the
///     slug is `<parent_dir>_<name>`. Missing packages are reported with
///     the dorny entry that should be added (including transitive deps).
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

    // Required-job consistency check. Name-based: if a workflow has a
    // top-level job keyed `required`, every other top-level job must
    // appear in its `needs:` list. Runs unconditionally for every
    // workflow file, independent of static-vs-dynamic coverage style.
    final requiredJobErrors = _findRequiredJobErrors(workflowFiles);

    if (dynamicWorkflows.isNotEmpty) {
      stdout.writeln(
        'Using dynamic coverage via ${dynamicWorkflows.join(', ')} — '
        'all ${allPackages.length} packages covered at runtime.',
      );
      if (requiredJobErrors.isNotEmpty) {
        _printRequiredJobErrors(requiredJobErrors);
        return 1;
      }
      return 0;
    }

    final slugs = computePackageSlugs(
      packages: allPackages,
      repoRoot: repoRoot,
    );
    final missing = <PackageDescription>[];

    for (final pkg in allPackages) {
      if (ignoreSet.contains(pkg.name)) continue;
      final slug = slugs[pkg]!;
      final workflows = coverageMap[slug];
      if (workflows != null) {
        final label = slug == pkg.name ? pkg.name : '${pkg.name} ($slug)';
        stdout.writeln('OK: $label (${workflows.join(', ')})');
      } else {
        missing.add(pkg);
      }
    }

    if (missing.isEmpty) {
      stdout.writeln('\nAll packages have CI coverage.');
      if (requiredJobErrors.isNotEmpty) {
        _printRequiredJobErrors(requiredJobErrors);
        return 1;
      }
      return 0;
    }

    stdout.writeln();
    final resolver = DependencyResolver(repoRoot);

    for (final pkg in missing) {
      final packageDir = posixRelative(pkg.rootPath, from: repoRoot);
      final deps = resolver.resolve(packageDir);
      final sortedDeps = deps.toList()..sort();
      final slug = slugs[pkg]!;
      final label = slug == pkg.name ? pkg.name : '${pkg.name} ($slug)';

      stdout
        ..writeln('MISSING: $label')
        ..writeln('  Add this entry to a dorny paths-filter block:')
        ..writeln('            $slug:');
      for (final dep in sortedDeps) {
        stdout.writeln('              - $dep/**');
      }
      stdout.writeln();
    }

    stderr.writeln(
      '${missing.length} package(s) missing from CI coverage.',
    );
    if (requiredJobErrors.isNotEmpty) {
      _printRequiredJobErrors(requiredJobErrors);
    }
    return 1;
  }

  /// For each workflow file, if a top-level job named `required` is
  /// present, returns the names of any other top-level jobs that are
  /// missing from its `needs:` list. Result is keyed by workflow file
  /// name. Workflows without a `required` job are absent from the map.
  ///
  /// The `required` job is the [--required] aggregator emitted by
  /// `generate`. It exists to be the single check listed in branch
  /// protection. If a job is missing from its `needs:`, that job's
  /// status is silently ignored by the aggregator and branch
  /// protection — exactly the silent failure mode this check guards
  /// against.
  Map<String, List<String>> _findRequiredJobErrors(List<File> workflowFiles) {
    final errors = <String, List<String>>{};
    for (final file in workflowFiles) {
      final fileName = p.basename(file.path);
      final YamlMap doc;
      try {
        final loaded = loadYaml(file.readAsStringSync());
        if (loaded is! YamlMap) continue;
        doc = loaded;
      } on YamlException {
        // Skip files we can't parse — verify isn't a YAML linter.
        continue;
      }

      final jobs = doc['jobs'];
      if (jobs is! YamlMap) continue;
      if (!jobs.containsKey('required')) continue;

      final requiredJob = jobs['required'];
      if (requiredJob is! YamlMap) continue;

      // `needs:` may be a scalar (single dependency) or a list. Normalize.
      final rawNeeds = requiredJob['needs'];
      final needsSet = <String>{
        if (rawNeeds is String) rawNeeds,
        if (rawNeeds is YamlList)
          for (final n in rawNeeds) n.toString(),
      };

      final missing = <String>[];
      for (final key in jobs.keys) {
        final jobName = key.toString();
        if (jobName == 'required') continue;
        if (!needsSet.contains(jobName)) missing.add(jobName);
      }
      if (missing.isNotEmpty) errors[fileName] = missing;
    }
    return errors;
  }

  void _printRequiredJobErrors(Map<String, List<String>> errors) {
    stderr.writeln();
    for (final entry in errors.entries) {
      stderr
        ..writeln('MISSING from required.needs in ${entry.key}:')
        ..writeln('  ${entry.value.join(', ')}');
    }
    stderr.writeln(
      '\n`required` job must depend on every other job in the workflow. '
      'Re-run `shorebird_ci generate --required` to regenerate.',
    );
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
