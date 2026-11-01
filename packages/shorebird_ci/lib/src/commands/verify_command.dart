import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/activate_pin.dart';
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/dorny_filter.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/package_slug.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:shorebird_ci/src/version.dart';
import 'package:yaml/yaml.dart';

/// Marker comment that the `generate` command writes into dynamic
/// workflows. Verify uses this to detect dynamic coverage instead of
/// substring-searching for the call (which falsely matches comments,
/// `run: echo "..."`, and similar).
const dynamicCoverageMarker = '# shorebird_ci-managed: dynamic';

/// Verifies that every discovered package has CI coverage somewhere in
/// `.github/workflows/`, and that any `required` aggregator job stays
/// in sync with the rest of the workflow.
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
///
/// A dynamic workflow must also run `bloc lint` if any package has a
/// `bloc_lint` dev dependency, since `generate` leaves the bloc steps
/// out of repos where no package uses it.
///
/// Before any of that, every workflow's `dart pub global activate
/// shorebird_ci` line must name the version running here. CI activates
/// the pin and a developer activates whatever they last installed, so
/// without this check a local pass says nothing about CI's.
///
/// In addition, if any workflow file has a top-level job keyed
/// `required`, every other top-level job in that file must appear in
/// its `needs:`, and every entry in `needs:` must match a real
/// top-level job. The aggregator is the single check listed in branch
/// protection, so drift in either direction silently breaks the gate.
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
  String get description =>
      'Verify package CI coverage and `required` aggregator consistency';

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
    // Each workflow's static filters, mapped to their path patterns.
    final filtersByWorkflow = <String, Map<String, Set<String>>>{};
    final workflowFiles =
        workflowDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final dynamicWorkflows = <String>[];
    var dynamicRunsBlocLint = false;
    final otherPins = <String, List<String>>{};
    final unpinned = <String>[];

    for (final file in workflowFiles) {
      final content = file.readAsStringSync();
      final fileName = p.basename(file.path);

      final pins = findActivatePins(content);
      final others = pins.versions.difference({packageVersion}).toList()
        ..sort();
      if (others.isNotEmpty) otherPins[fileName] = others;
      if (pins.hasUnpinned) unpinned.add(fileName);

      if (_usesDynamicCoverage(content)) {
        dynamicWorkflows.add(fileName);
        dynamicRunsBlocLint |= content.contains('bloc lint');
        continue;
      }

      final filters = extractDornyFilters(content);
      filtersByWorkflow[fileName] = filters;
      for (final name in filters.keys) {
        coverageMap.putIfAbsent(name, () => []).add(fileName);
      }
    }

    // Ahead of the coverage checks, so their results are never reported as
    // if the version CI runs had produced them.
    if (otherPins.isNotEmpty) {
      for (final MapEntry(key: fileName, value: versions)
          in otherPins.entries) {
        stderr.writeln(
          'PIN: $fileName runs shorebird_ci ${versions.join(', ')}; this is '
          '$packageVersion. A pass here would not be a pass in CI. Run '
          '`dart pub global activate shorebird_ci ${versions.first}` to ask '
          'what CI asks, or `shorebird_ci generate` to move CI to '
          '$packageVersion.',
        );
      }
      return 1;
    }
    if (unpinned.isNotEmpty) {
      stdout.writeln(
        'Note: ${unpinned.join(', ')} activates shorebird_ci with no '
        'version, so CI runs whatever was published last rather than '
        '$packageVersion. `shorebird_ci generate` pins it.',
      );
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
      // `generate` emits the bloc steps only when some package uses
      // bloc_lint, so a package that adds it later would pass CI
      // without ever being linted.
      final blocPackages = [
        for (final pkg in allPackages)
          if (RepositoryAnalyzer.dependsOnBlocLint(root: pkg.root)) pkg.name,
      ];
      final missingBlocLint = blocPackages.isNotEmpty && !dynamicRunsBlocLint;
      if (missingBlocLint) {
        stderr.writeln(
          'MISSING bloc lint: ${blocPackages.join(', ')} depend on '
          'bloc_lint, but ${dynamicWorkflows.join(', ')} never runs '
          '`bloc lint`. Re-run `shorebird_ci generate` to regenerate.',
        );
      }
      if (requiredJobErrors.isNotEmpty) {
        _printRequiredJobErrors(requiredJobErrors);
        return 1;
      }
      return missingBlocLint ? 1 : 0;
    }

    final slugs = computePackageSlugs(
      packages: allPackages,
      repoRoot: repoRoot,
    );
    final missing = <PackageDescription>[];
    final resolver = DependencyResolver(repoRoot);
    // Filters that don't match every package their job depends on, so
    // a change to one of those packages skips the job. Each workflow's
    // filter is checked on its own: its jobs run only on its matches.
    final drift = <String, List<String>>{};

    for (final pkg in allPackages) {
      if (ignoreSet.contains(pkg.name)) continue;
      final slug = slugs[pkg]!;
      final workflows = coverageMap[slug];
      if (workflows == null) {
        missing.add(pkg);
        continue;
      }
      final label = slug == pkg.name ? pkg.name : '${pkg.name} ($slug)';
      final packageDir = posixRelative(pkg.rootPath, from: repoRoot);
      final deps = resolver.resolve(packageDir);
      final files = resolver.workspaceFiles(packageDir);
      var covered = true;
      for (final workflow in workflows) {
        final patterns = filtersByWorkflow[workflow]![slug]!;
        final uncovered = [
          for (final dep in deps)
            if (!_covers(patterns, dep, isDirectory: true)) '$dep/**',
          for (final file in files)
            if (!_covers(patterns, file, isDirectory: false)) file,
        ]..sort();
        if (uncovered.isNotEmpty) {
          covered = false;
          drift['$label filter in $workflow'] = uncovered;
        }
      }
      if (covered) {
        stdout.writeln('OK: $label (${workflows.join(', ')})');
      }
    }

    if (drift.isNotEmpty) {
      for (final MapEntry(key: label, value: deps) in drift.entries) {
        stderr.writeln(
          'DRIFT: the $label misses files its package depends on. '
          'Add to it:',
        );
        for (final dep in deps) {
          stderr.writeln('              - $dep');
        }
      }
      stderr.writeln(
        '${drift.length} filter(s) miss files their package depends on.',
      );
    }

    if (missing.isEmpty) {
      if (drift.isNotEmpty) {
        if (requiredJobErrors.isNotEmpty) {
          _printRequiredJobErrors(requiredJobErrors);
        }
        return 1;
      }
      stdout.writeln('\nAll packages have CI coverage.');
      if (requiredJobErrors.isNotEmpty) {
        _printRequiredJobErrors(requiredJobErrors);
        return 1;
      }
      return 0;
    }

    stdout.writeln();

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
      for (final file in resolver.workspaceFiles(packageDir).toList()..sort()) {
        stdout.writeln('              - $file');
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

  /// For each workflow file w/ a top-level `required:` job, returns
  /// the symmetric drift between its `needs:` list and the set of
  /// other top-level jobs in the same file.
  ///
  /// `missing` are top-level jobs absent from `needs:` — they run but
  /// their status is silently ignored by the aggregator and branch
  /// protection, the exact failure mode this check guards against.
  ///
  /// `stale` are entries in `needs:` w/ no matching top-level job,
  /// usually a typo. GHA itself rejects these at runtime, but catching
  /// them at verify time keeps the feedback loop tight.
  ///
  /// Workflows without a `required:` job are absent from the result.
  Map<String, _RequiredJobReport> _findRequiredJobErrors(
    List<File> workflowFiles,
  ) {
    final errors = <String, _RequiredJobReport>{};
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
      if (requiredJob is! YamlMap) {
        // `required:` exists as a key but has no map body (e.g. `null`,
        // a scalar string, or a list). That's a malformed aggregator —
        // GHA wouldn't run it, and verify can't reason about its
        // `needs:`. Surface it instead of silently skipping.
        errors[fileName] = _RequiredJobReport(
          missing: const [],
          stale: const [],
          isMalformed: true,
        );
        continue;
      }

      // `needs:` may be a scalar (single dependency), a list, missing
      // entirely, or null. Normalize to a set of strings; unrecognized
      // types fall through to an empty set, which surfaces every other
      // job as missing — the correct conservative outcome.
      final rawNeeds = requiredJob['needs'];
      final needsList = <String>[
        if (rawNeeds is String) rawNeeds,
        if (rawNeeds is YamlList)
          for (final n in rawNeeds) n.toString(),
      ];
      final needsSet = needsList.toSet();

      final jobNames = <String>{
        for (final key in jobs.keys) key.toString(),
      };

      final missing = <String>[
        for (final job in jobNames)
          if (job != 'required' && !needsSet.contains(job)) job,
      ];
      final stale = <String>[
        for (final need in needsList)
          if (!jobNames.contains(need)) need,
      ];

      if (missing.isNotEmpty || stale.isNotEmpty) {
        errors[fileName] = _RequiredJobReport(
          missing: missing,
          stale: stale,
        );
      }
    }
    return errors;
  }

  void _printRequiredJobErrors(Map<String, _RequiredJobReport> errors) {
    stderr.writeln();
    for (final entry in errors.entries) {
      final report = entry.value;
      if (report.isMalformed) {
        stderr.writeln(
          'MALFORMED `required:` job in ${entry.key}: value is not a '
          'map. Expected a job definition w/ `needs:` and `runs-on:`.',
        );
        continue;
      }
      if (report.missing.isNotEmpty) {
        stderr
          ..writeln('MISSING from required.needs in ${entry.key}:')
          ..writeln('  ${report.missing.join(', ')}');
      }
      if (report.stale.isNotEmpty) {
        stderr
          ..writeln('STALE entries in required.needs in ${entry.key}:')
          ..writeln('  ${report.stale.join(', ')}')
          ..writeln('  (these reference jobs that do not exist in the file)');
      }
    }
    stderr.writeln(
      '\n`required` job must depend on every other job in the workflow, '
      'and every entry in `needs:` must match a real job. '
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

/// Per-workflow drift report for the `required:` aggregator.
class _RequiredJobReport {
  _RequiredJobReport({
    required this.missing,
    required this.stale,
    this.isMalformed = false,
  });

  /// Top-level jobs that exist in the workflow but are absent from
  /// `required.needs`. They run but don't gate the aggregator.
  final List<String> missing;

  /// Entries listed in `required.needs` that don't match any top-level
  /// job in the workflow. GHA itself rejects these at runtime.
  final List<String> stale;

  /// The `required:` key exists but its value isn't a job map. When
  /// true, `missing` and `stale` are empty — there's nothing structured
  /// to compare.
  final bool isMalformed;
}

/// Whether one of a dorny filter's [patterns] matches the repo-relative
/// [path] (every file in it, if [isDirectory]): the path itself, a
/// `<dir>/**` for it or one of its ancestors, or `**`.
bool _covers(Set<String> patterns, String path, {required bool isDirectory}) {
  for (var pattern in patterns) {
    if (pattern.startsWith('./')) pattern = pattern.substring(2);
    if (pattern == '**') return true;
    if (pattern == path && !isDirectory) return true;
    if (!pattern.endsWith('/**')) continue;
    final dir = pattern.substring(0, pattern.length - 3);
    if ((isDirectory && path == dir) || path.startsWith('$dir/')) return true;
  }
  return false;
}
