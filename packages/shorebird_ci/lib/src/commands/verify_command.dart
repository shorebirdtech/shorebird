import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/activate_pin.dart';
import 'package:shorebird_ci/src/commands/generate_command.dart';
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/dorny_filter.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/package_slug.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:shorebird_ci/src/repository_description.dart';
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
///
/// Finally, every workflow carrying the `--style static` marker is
/// rebuilt from the repository and compared against what is checked in,
/// whatever coverage style the rest of the repository uses. The
/// coverage checks above only ask whether each filter is a superset of
/// its package's dep graph, so a hand-added input, a job generation no
/// longer writes, or a declaration somebody forgot all pass them and
/// then vanish at the next `generate` run.
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
    // Workflows `generate --style static` wrote, by file name.
    final generatedStaticWorkflows = <String>[];
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

      if (content.contains(staticWorkflowMarker)) {
        generatedStaticWorkflows.add(fileName);
      }

      // Read from every workflow, dynamic ones included, so a file
      // carrying both markers is still rebuilt below. Only a workflow
      // without the dynamic marker has its filters count as coverage.
      final filters = extractDornyFilters(content);
      filtersByWorkflow[fileName] = filters;

      if (_usesDynamicCoverage(content)) {
        dynamicWorkflows.add(fileName);
        dynamicRunsBlocLint |= content.contains('bloc lint');
        continue;
      }

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
      stderr.writeln(
        'Nothing else was checked: coverage and `required` are reported '
        'against the version CI runs, not this one.',
      );
      return 1;
    }
    if (unpinned.isNotEmpty) {
      stdout.writeln(
        'Note: ${unpinned.join(', ')} activates shorebird_ci with no exact '
        'version, so CI runs whatever that resolves to rather than '
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

    // Also independent of coverage style: a generated static
    // orchestrator is rebuilt and compared wherever it sits, including
    // beside a workflow that covers packages dynamically.
    final slugs = computePackageSlugs(
      packages: allPackages,
      repoRoot: repoRoot,
    );
    // The orchestrator is the generated workflow holding the dorny
    // filters; the reusable workflows it calls hold none.
    final orchestrators = [
      for (final fileName in generatedStaticWorkflows)
        if (filtersByWorkflow[fileName]?.isNotEmpty ?? false) fileName,
    ];
    final regenerationDrift = _findRegenerationDrift(
      repository: repository,
      packages: allPackages,
      slugs: slugs,
      orchestrators: orchestrators,
    );
    final orchestratorPath = orchestrators.isEmpty
        ? null
        : p.posix.join('.github', 'workflows', orchestrators.first);

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
      if (regenerationDrift.isNotEmpty) {
        _printRegenerationDrift(regenerationDrift);
      }
      if (requiredJobErrors.isNotEmpty) {
        _printRequiredJobErrors(requiredJobErrors);
      }
      return missingBlocLint ||
              regenerationDrift.isNotEmpty ||
              requiredJobErrors.isNotEmpty
          ? 1
          : 0;
    }

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
      final files = {
        ...resolver.workspaceFiles(packageDir),
        ...resolver.extraInputs(packageDir),
      };
      var covered = true;
      for (final workflow in workflows) {
        final patterns = filtersByWorkflow[workflow]![slug]!;
        final uncovered = [
          for (final dep in deps)
            if (resolver.isSubmodule(dep))
              if (!_covers(patterns, dep, isDirectory: false) &&
                  !_covers(patterns, dep, isDirectory: true))
                dep
              else
                ...const <String>[]
            else if (!_covers(patterns, dep, isDirectory: true))
              '$dep/**',
          for (final file in files)
            if (file.endsWith('/**'))
              if (!_covers(
                patterns,
                file.substring(0, file.length - 3),
                isDirectory: true,
              ))
                file
              else
                ...const <String>[]
            else if (!_covers(patterns, file, isDirectory: false))
              file,
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
      if (drift.isEmpty && regenerationDrift.isEmpty) {
        stdout.writeln('\nAll packages have CI coverage.');
      }
    } else {
      stdout.writeln();

      for (final pkg in missing) {
        final packageDir = posixRelative(pkg.rootPath, from: repoRoot);
        final entries = suggestedFilterEntries(
          resolver: resolver,
          packageDir: packageDir,
          isFlutter: RepositoryAnalyzer.dependsOnFlutter(root: pkg.root),
          orchestratorPath: orchestratorPath,
        );
        final slug = slugs[pkg]!;
        final label = slug == pkg.name ? pkg.name : '${pkg.name} ($slug)';

        stdout
          ..writeln('MISSING: $label')
          ..writeln('  Add this entry to a dorny paths-filter block:')
          ..writeln('            $slug:');
        for (final entry in entries) {
          stdout.writeln('              - $entry');
        }
        stdout.writeln();
      }

      stderr.writeln(
        '${missing.length} package(s) missing from CI coverage.',
      );
    }

    if (regenerationDrift.isNotEmpty) {
      _printRegenerationDrift(regenerationDrift);
    }
    if (requiredJobErrors.isNotEmpty) {
      _printRequiredJobErrors(requiredJobErrors);
    }

    final failed =
        missing.isNotEmpty ||
        drift.isNotEmpty ||
        regenerationDrift.isNotEmpty ||
        requiredJobErrors.isNotEmpty;
    return failed ? 1 : 0;
  }

  /// Rebuilds what `generate --style static` would write for each
  /// orchestrator in [orchestrators] and returns, per repo-relative
  /// path, where the checked-in copy parts company with it.
  ///
  /// Every input generation reads lives in the tree: the packages, their
  /// dep graph, and the `shorebird_ci:` blocks in `pubspec.yaml`. So a
  /// difference is a hand edit or a declaration somebody forgot, and
  /// either way the next `generate` run overwrites it.
  Map<String, GeneratedWorkflowDiff> _findRegenerationDrift({
    required RepositoryDescription repository,
    required List<PackageDescription> packages,
    required Map<PackageDescription, String> slugs,
    required List<String> orchestrators,
  }) {
    final diffs = <String, GeneratedWorkflowDiff>{};
    for (final orchestrator in orchestrators) {
      final generated = buildStaticWorkflowFiles(
        repository,
        outputPath: p.posix.join('.github', 'workflows', orchestrator),
        codecovTokenSecret: repository.ciConfig.codecovTokenSecret,
        emitRequiredJob: repository.ciConfig.emitRequiredJob,
        fatalInfos: repository.ciConfig.fatalInfos,
        packages: packages,
        slugs: slugs,
      );
      for (final MapEntry(key: path, value: expected) in generated.entries) {
        final file = File(p.join(repoRoot, path));
        final diff = diffGeneratedWorkflow(
          expected: expected,
          actual: file.existsSync() ? file.readAsStringSync() : null,
        );
        if (diff != null) diffs[path] = diff;
      }
    }
    return diffs;
  }

  void _printRegenerationDrift(Map<String, GeneratedWorkflowDiff> diffs) {
    stderr.writeln();
    for (final MapEntry(key: path, value: diff) in diffs.entries) {
      final actual = diff.actual;
      if (actual == null) {
        stderr.writeln(
          'REGENERATE: $path is missing. '
          '`shorebird_ci generate --style static` writes it.',
        );
        continue;
      }
      stderr.writeln(
        'REGENERATE: $path is not what generation writes, '
        'from line ${diff.line}:',
      );
      for (final line in _diffWindow(actual)) {
        stderr.writeln('  checked in: $line');
      }
      for (final line in _diffWindow(diff.expected)) {
        stderr.writeln('   generated: $line');
      }
    }
    stderr.writeln(
      '\nDeclare the input in the `shorebird_ci:` block of the package or '
      'repository `pubspec.yaml`, or re-run `shorebird_ci generate '
      '--style static` and commit what it writes.',
    );
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

/// The dorny filter entries `generate --style static` writes for the
/// package at [packageDir], which is what `verify` offers for a package
/// missing from every filter.
///
/// Both workflow paths are in there because a job declared in the
/// orchestrator and run by a reusable workflow has to re-run when either
/// changes. [orchestratorPath] is null for a repo whose static workflows
/// are hand-rolled, which has neither path to name.
List<String> suggestedFilterEntries({
  required DependencyResolver resolver,
  required String packageDir,
  required bool isFlutter,
  required String? orchestratorPath,
}) {
  final reusable = orchestratorPath == null
      ? null
      : isFlutter
      ? '.github/workflows/_shorebird_ci_flutter.yaml'
      : '.github/workflows/_shorebird_ci_dart.yaml';
  return <String>{
    ?orchestratorPath,
    ...resolver.filterPaths(packageDir, workflowFile: reusable),
  }.toList()..sort();
}

/// Where a checked-in workflow and its regenerated copy part company.
///
/// `line` is 1-based, `actual` is the checked-in window or null when the
/// file is absent from the tree, and `expected` is what generation
/// writes in its place.
typedef GeneratedWorkflowDiff = ({
  int line,
  List<String>? actual,
  List<String> expected,
});

/// The lines where [expected] and [actual] first and last differ, with
/// their common prefix and suffix trimmed off, or null when they match.
GeneratedWorkflowDiff? diffGeneratedWorkflow({
  required String expected,
  required String? actual,
}) {
  if (actual == null) return (line: 1, actual: null, expected: const []);

  final expectedLines = expected.split('\n');
  final actualLines = actual.split('\n');

  var prefix = 0;
  while (prefix < expectedLines.length &&
      prefix < actualLines.length &&
      _sameLine(expectedLines[prefix], actualLines[prefix])) {
    prefix++;
  }
  if (prefix == expectedLines.length && prefix == actualLines.length) {
    return null;
  }

  var suffix = 0;
  while (suffix < expectedLines.length - prefix &&
      suffix < actualLines.length - prefix &&
      _sameLine(
        expectedLines[expectedLines.length - 1 - suffix],
        actualLines[actualLines.length - 1 - suffix],
      )) {
    suffix++;
  }

  return (
    line: prefix + 1,
    actual: actualLines.sublist(prefix, actualLines.length - suffix),
    expected: expectedLines.sublist(prefix, expectedLines.length - suffix),
  );
}

/// Two generated lines that say the same thing. An action reference
/// compares by action alone: every `uses:` ref moves past the pins in
/// `action_versions.dart` as soon as it is written, first by
/// `generate`'s own update step and then by Dependabot, so a bumped pin
/// is that working rather than drift.
bool _sameLine(String a, String b) =>
    _withoutActionRef(a) == _withoutActionRef(b);

final _actionRefPattern = RegExp(r'^(\s*(?:- )?uses: [^@\s]+)@\S+');

String _withoutActionRef(String line) =>
    _actionRefPattern.firstMatch(line)?.group(1) ?? line;

/// At most ten lines of a difference, so a file that differs wholesale
/// reports somewhere to look rather than itself.
List<String> _diffWindow(List<String> lines) {
  if (lines.isEmpty) return const ['(nothing)'];
  if (lines.length <= 10) return lines;
  return [...lines.take(10), '... ${lines.length - 10} more lines'];
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
