import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/action_versions.dart';
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/flutter_version_resolver.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/package_slug.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:shorebird_ci/src/repository_description.dart';
import 'package:shorebird_ci/src/version.dart';

/// Generates a GitHub Actions CI workflow for a Dart/Flutter repository.
class GenerateCommand extends Command<int> with RepoRootOption {
  /// Creates a [GenerateCommand]. The optional [resolveLatestRelease] is
  /// exposed for tests so they don't have to hit the live GitHub API
  /// when verifying the `--update-actions` path.
  GenerateCommand({LatestReleaseResolver? resolveLatestRelease})
    : _resolveLatestRelease = resolveLatestRelease {
    addRepoRootOption();
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path.',
        defaultsTo: '.github/workflows/shorebird_ci.yaml',
      )
      ..addOption(
        'style',
        help: 'Workflow style to generate.',
        allowed: ['dynamic', 'static'],
        defaultsTo: 'dynamic',
      )
      ..addFlag(
        'dry-run',
        help:
            'Print the generated workflow to stdout '
            'instead of writing to a file.',
      )
      ..addFlag(
        'no-update-actions',
        help: '''
Skip the post-generate step that queries GitHub for each action's
latest release and pins it in place. Without it, generate writes the
commit pins built into this version of shorebird_ci. Either way every
action is pinned to a commit SHA. Pass this flag in offline
environments.''',
        negatable: false,
      )
      ..addOption(
        'codecov-token-secret',
        help: r'''
Name of the GitHub Actions secret holding the Codecov upload token.
When set, the codecov-action step receives
`token: ${{ secrets.<NAME> }}` in both --style dynamic (default) and
--style static output. In --style static, the generated orchestrator
additionally emits `secrets: inherit` on each reusable workflow call
so the secret is reachable inside the reusable workflow. When unset
(the default), no token plumbing is emitted. Refer to Codecov's docs
for whether your repo requires a token to upload.''',
      )
      ..addFlag(
        'required',
        help: '''
Emit a `required` aggregator job at the end of the workflow that
depends on every other job. Use it as the single required check in
branch protection: the aggregator fails when any dependency reports
`failure` or `cancelled`, and passes when dependencies succeed or
were skipped. Skipped sub-jobs are the common case since per-package
jobs only run on touched paths. The `required` job key is reserved
when this flag is set, so generation fails if any package slug
resolves to `required`. Skip the flag and any package slug is fine.''',
        negatable: false,
      );
  }

  final LatestReleaseResolver? _resolveLatestRelease;

  @override
  String get name => 'generate';

  @override
  String get description => 'Generate a GitHub Actions CI workflow';

  @override
  Future<int> run() async {
    final outputPath = argResults!['output'] as String;
    final dryRun = argResults!.flag('dry-run');
    final style = argResults!['style'] as String;
    final codecovTokenSecret = argResults!['codecov-token-secret'] as String?;
    final emitRequiredJob = argResults!.flag('required');

    final analyzer = RepositoryAnalyzer();
    final repoDir = Directory(repoRoot);
    final repository = analyzer.analyze(
      repositoryRoot: repoDir,
    );

    if (repository.packages.isEmpty) {
      stderr.writeln('No Dart packages found in $repoRoot');
      return 1;
    }

    final sortedPackages = repository.packages.toList()
      ..sort(
        (PackageDescription a, PackageDescription b) =>
            a.name.compareTo(b.name),
      );

    // Slugs only matter for static-mode workflow generation: in dynamic
    // mode jobs are keyed `setup` / `dart_ci` / `flutter_ci` / `cspell`,
    // never by per-package slug, so a package named `required` cannot
    // collide w/ the aggregator there. Compute (and collision-check)
    // only when static.
    Map<PackageDescription, String>? slugs;
    if (style == 'static') {
      slugs = computePackageSlugs(
        packages: sortedPackages,
        repoRoot: repoRoot,
      );
      if (emitRequiredJob) {
        // `required` is the reserved job key for the --required
        // aggregator. A package slug that resolves to `required` would
        // emit a duplicate YAML key and silently overwrite the
        // aggregator. Fail loudly so the user renames the package
        // before generation.
        final colliding = slugs.entries
            .where((e) => e.value == 'required')
            .map((e) => e.key.name)
            .toList();
        if (colliding.isNotEmpty) {
          stderr.writeln(
            'Package slug `required` collides with the --required '
            'aggregator job. Rename the colliding package(s): '
            '${colliding.join(', ')}',
          );
          return 1;
        }
      }
    }

    // Each builder returns a map of repo-relative path → file content.
    // Dynamic returns a single entry; static returns a main workflow
    // plus one or two reusable workflows.
    //
    // Actions are emitted at the commit pins in action_versions.dart;
    // the update step below moves them to each action's latest release.
    final files = style == 'static'
        ? _buildStaticFiles(
            repository,
            outputPath: outputPath,
            codecovTokenSecret: codecovTokenSecret,
            emitRequiredJob: emitRequiredJob,
            packages: sortedPackages,
            slugs: slugs!,
          )
        : {
            outputPath: _buildDynamicYaml(
              repository,
              codecovTokenSecret: codecovTokenSecret,
              emitRequiredJob: emitRequiredJob,
            ),
          };

    if (dryRun) {
      final sortedKeys = files.keys.toList()..sort();
      for (final key in sortedKeys) {
        stdout
          ..writeln('# ──── $key ────')
          ..write(files[key])
          ..writeln();
      }
      return 0;
    }

    for (final entry in files.entries) {
      final outputFile = File(p.join(repoRoot, entry.key));
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(entry.value);
      stderr.writeln('Wrote ${outputFile.path}');
    }

    _ensureDependabotConfig(repoRoot);

    if (!argResults!.flag('no-update-actions')) {
      await _bumpActionVersions(
        files: files.keys.map((rel) => File(p.join(repoRoot, rel))),
      );
    }

    return 0;
  }

  /// Rewrites each file in place w/ latest-release action pins. Best-effort:
  /// network failures leave the file untouched (handled by
  /// [updateActionVersions], which returns null per-action on lookup
  /// failure).
  Future<void> _bumpActionVersions({required Iterable<File> files}) async {
    stderr.writeln('Updating action versions...');
    for (final file in files) {
      final before = file.readAsStringSync();
      final after = await updateActionVersions(
        before,
        resolveLatestRelease: _resolveLatestRelease,
      );
      if (before != after) file.writeAsStringSync(after);
    }
  }

  /// Creates `.github/dependabot.yml` with a `github-actions` ecosystem
  /// entry if the file doesn't already exist.
  void _ensureDependabotConfig(String repoRoot) {
    final file = File(p.join(repoRoot, '.github', 'dependabot.yml'));
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      if (!content.contains('github-actions')) {
        stderr.writeln(
          'Note: .github/dependabot.yml exists but has no '
          'github-actions entry. Consider adding one so action '
          'versions in your workflow stay up to date.',
        );
      }
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
# Dependabot auto-updates action versions in your workflows.
# https://docs.github.com/en/code-security/dependabot
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      gha-deps:
        patterns:
          - "*"
''');
    stderr.writeln('Wrote ${file.path}');
  }

  // ── Static (dorny/paths-filter + reusable workflows) ─────────────
  //
  // Produces a full drop-in workflow setup: a main workflow that uses
  // dorny/paths-filter to pick which packages are affected and a thin
  // per-package job that calls a reusable workflow. The reusable
  // workflow(s) hold the actual CI steps so we don't duplicate them
  // across N named jobs.

  Map<String, String> _buildStaticFiles(
    RepositoryDescription repository, {
    required String outputPath,
    required String? codecovTokenSecret,
    required bool emitRequiredJob,
    required List<PackageDescription> packages,
    required Map<PackageDescription, String> slugs,
  }) {
    final hasDart = packages.any(
      (pkg) => !RepositoryAnalyzer.dependsOnFlutter(root: pkg.root),
    );
    final hasFlutter = packages.any(
      (pkg) => RepositoryAnalyzer.dependsOnFlutter(root: pkg.root),
    );

    final files = <String, String>{
      outputPath: _buildStaticMainYaml(
        repository: repository,
        packages: packages,
        codecovTokenSecret: codecovTokenSecret,
        emitRequiredJob: emitRequiredJob,
        slugs: slugs,
      ),
    };
    if (hasDart) {
      files['.github/workflows/_shorebird_ci_dart.yaml'] =
          _buildDartReusableWorkflow(
            hasBlocLint: _anyDependsOnBlocLint(packages, isFlutter: false),
            hasCodecov: repository.hasCodecov,
            codecovTokenSecret: codecovTokenSecret,
          );
    }
    if (hasFlutter) {
      files['.github/workflows/_shorebird_ci_flutter.yaml'] =
          _buildFlutterReusableWorkflow(
            hasBlocLint: _anyDependsOnBlocLint(packages, isFlutter: true),
            hasCodecov: repository.hasCodecov,
            codecovTokenSecret: codecovTokenSecret,
          );
    }
    return files;
  }

  String _buildStaticMainYaml({
    required RepositoryDescription repository,
    required List<PackageDescription> packages,
    required String? codecovTokenSecret,
    required bool emitRequiredJob,
    required Map<PackageDescription, String> slugs,
  }) {
    final emitSecretsInherit =
        codecovTokenSecret != null &&
        codecovTokenSecret.isNotEmpty &&
        repository.hasCodecov;
    final resolver = DependencyResolver(repository.root.path);

    final buffer = StringBuffer()
      ..write('''
# Generated by shorebird_ci --style static. Safe to edit.
# Run `shorebird_ci verify` to check for dep graph drift.
name: Shorebird CI

$_concurrencyBlock
on:
  pull_request:
    branches:
      - main
  # Checks run on the queue's own temp branch, not the PR. Without this
  # trigger the required contexts never report there and the queue
  # ejects every PR at the timeout.
  merge_group:
    types: [checks_requested]
  push:
    branches:
      - main

$_readOnlyPermissionsBlock
jobs:
  changes:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      # dorny/paths-filter lists a pull request's changed files through the API.
      pull-requests: read
    outputs:
''');

    for (final package in packages) {
      final slug = slugs[package]!;
      buffer.writeln('      $slug: \${{ steps.filter.outputs.$slug }}');
    }

    // Verify first so we fail fast if the dorny filters below have
    // drifted from the Dart dep graph. Without this, a new package or
    // a changed `path:` dependency would silently go uncovered.
    buffer.write('''
    steps:
      - uses: $checkoutAction
        with:
          # Full history so dorny/paths-filter can diff on push events.
          fetch-depth: 0
      - uses: $setupDartAction
      - run: dart pub global activate shorebird_ci $packageVersion
      - name: Verify CI coverage
        run: shorebird_ci verify
      - uses: $pathsFilterAction
        id: filter
        with:
          filters: |
''');

    for (final package in packages) {
      final packageDir = posixRelative(
        package.rootPath,
        from: repository.root.path,
      );
      final sortedDeps = resolver.resolve(packageDir).toList()..sort();
      final slug = slugs[package]!;

      buffer.writeln('            $slug:');
      for (final dep in sortedDeps) {
        buffer.writeln('              - $dep/**');
      }
      final workspaceFiles = resolver.workspaceFiles(packageDir).toList()
        ..sort();
      for (final file in workspaceFiles) {
        buffer.writeln('              - $file');
      }
    }
    buffer.writeln();

    for (final package in packages) {
      final packageDir = posixRelative(
        package.rootPath,
        from: repository.root.path,
      );
      final isFlutter = RepositoryAnalyzer.dependsOnFlutter(
        root: package.root,
      );
      final subpackages =
          RepositoryAnalyzer.subpackages(package: package)
              .map((sub) => posixRelative(sub.rootPath, from: package.rootPath))
              .toList()
            ..sort();
      final reusable = isFlutter
          ? '_shorebird_ci_flutter.yaml'
          : '_shorebird_ci_dart.yaml';
      final slug = slugs[package]!;

      buffer.write('''
  $slug:
    needs: changes
    if: needs.changes.outputs.$slug == 'true'
    uses: ./.github/workflows/$reusable
    with:
      package_name: ${package.name}
      package_path: $packageDir
      has_unit_tests: ${RepositoryAnalyzer.hasUnitTests(root: package.root)}
      subpackages: "${subpackages.join(' ')}"
''');

      // The reusable workflow declares `has_bloc_lint` only when some
      // package of its SDK uses bloc_lint, and it defaults to false, so
      // pass it only where it's true.
      if (RepositoryAnalyzer.dependsOnBlocLint(root: package.root)) {
        buffer.writeln('      has_bloc_lint: true');
      }

      if (isFlutter) {
        final version = resolveFlutterVersion(
          packagePath: package.rootPath,
        );
        buffer
          ..writeln('      flutter_version: "${version ?? ''}"')
          ..writeln(
            '      has_integration_tests: '
            '${RepositoryAnalyzer.hasIntegrationTests(root: package.root)}',
          );
      }

      if (emitSecretsInherit) {
        buffer.writeln('    secrets: inherit');
      }

      buffer.writeln();
    }

    if (repository.cspellConfig != null) {
      _writeCspellJob(buffer, repository);
    }

    if (emitRequiredJob) {
      final needs = <String>[
        'changes',
        for (final package in packages) slugs[package]!,
        if (repository.cspellConfig != null) 'cspell',
      ];
      _writeRequiredJob(buffer, needs);
    }

    return buffer.toString();
  }

  String _buildDartReusableWorkflow({
    required bool hasBlocLint,
    required bool hasCodecov,
    required String? codecovTokenSecret,
  }) {
    final testStep = hasCodecov
        ? '''
      - name: Run Tests
        if: inputs.has_unit_tests
        working-directory: \${{ inputs.package_path }}
        # Pinned until https://github.com/dart-lang/tools/issues/2667 is fixed.
        run: |
          dart pub global activate coverage 1.15.1 && \\
          dart test --coverage=coverage && \\
          dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --check-ignore
      - if: inputs.has_unit_tests
        uses: $codecovAction
        with:
          flags: \${{ inputs.package_name }}
          working-directory: \${{ inputs.package_path }}
${_codecovTokenLine(codecovTokenSecret)}'''
        : r'''
      - if: inputs.has_unit_tests
        working-directory: ${{ inputs.package_path }}
        run: dart test
''';

    return '''
# Generated by shorebird_ci --style static. Safe to edit.
# Reusable workflow: CI steps for a single Dart package.
on:
  workflow_call:
    inputs:
      package_name:
        required: true
        type: string
      package_path:
        required: true
        type: string
${hasBlocLint ? _staticBlocLintInput : ''}      has_unit_tests:
        required: false
        default: true
        type: boolean
      subpackages:
        required: false
        default: ""
        type: string

$_readOnlyPermissionsBlock
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: $checkoutAction
        with:
          submodules: recursive
      - uses: $setupDartAction
${hasBlocLint ? _staticBlocToolsSetupStep : ''}      - name: Install Dependencies
        working-directory: \${{ inputs.package_path }}
        run: |
          dart pub get --no-example
          for sub in \${{ inputs.subpackages }}; do
            dart pub get --no-example -C \$sub
          done
      - working-directory: \${{ inputs.package_path }}
        run: dart format --set-exit-if-changed .
      - working-directory: \${{ inputs.package_path }}
        run: dart analyze --fatal-warnings .
${hasBlocLint ? _staticBlocLintStep : ''}$testStep''';
  }

  String _buildFlutterReusableWorkflow({
    required bool hasBlocLint,
    required bool hasCodecov,
    required String? codecovTokenSecret,
  }) {
    final testStep = hasCodecov
        ? '''
      - if: inputs.has_unit_tests
        working-directory: \${{ inputs.package_path }}
        run: flutter test --coverage
      - if: inputs.has_unit_tests
        uses: $codecovAction
        with:
          flags: \${{ inputs.package_name }}
          working-directory: \${{ inputs.package_path }}
${_codecovTokenLine(codecovTokenSecret)}'''
        : r'''
      - if: inputs.has_unit_tests
        working-directory: ${{ inputs.package_path }}
        run: flutter test
''';

    return '''
# Generated by shorebird_ci --style static. Safe to edit.
# Reusable workflow: CI steps for a single Flutter package.
on:
  workflow_call:
    inputs:
      package_name:
        required: true
        type: string
      package_path:
        required: true
        type: string
      flutter_version:
        required: false
        default: ""
        type: string
${hasBlocLint ? _staticBlocLintInput : ''}      has_integration_tests:
        required: false
        default: false
        type: boolean
      has_unit_tests:
        required: false
        default: true
        type: boolean
      subpackages:
        required: false
        default: ""
        type: string

$_readOnlyPermissionsBlock
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: $checkoutAction
        with:
          submodules: recursive
      - name: Setup Flutter
        uses: $flutterAction
        with:
          flutter-version: \${{ inputs.flutter_version || '' }}
          channel: \${{ inputs.flutter_version && '' || 'stable' }}
${hasBlocLint ? _staticBlocToolsSetupStep : ''}      - name: Install Dependencies
        working-directory: \${{ inputs.package_path }}
        run: |
          flutter pub get --no-example
          for sub in \${{ inputs.subpackages }}; do
            flutter pub get --no-example -C \$sub
          done
      - working-directory: \${{ inputs.package_path }}
        run: dart format --set-exit-if-changed .
      - working-directory: \${{ inputs.package_path }}
        run: flutter analyze .
${hasBlocLint ? _staticBlocLintStep : ''}$testStep      - name: Integration Tests
        if: inputs.has_integration_tests
        working-directory: \${{ inputs.package_path }}
        run: flutter test integration_test
''';
  }

  /// Whether any of the [packages] built with Flutter (or, when
  /// [isFlutter] is false, with plain Dart) has a bloc_lint dev
  /// dependency. Repos with none get no bloc input or steps, so their
  /// workflows don't install bloc_tools at all.
  static bool _anyDependsOnBlocLint(
    Iterable<PackageDescription> packages, {
    required bool isFlutter,
  }) => packages.any(
    (pkg) =>
        RepositoryAnalyzer.dependsOnFlutter(root: pkg.root) == isFlutter &&
        RepositoryAnalyzer.dependsOnBlocLint(root: pkg.root),
  );

  static const _staticBlocLintInput = '''
      has_bloc_lint:
        required: false
        default: false
        type: boolean
''';

  static const _staticBlocToolsSetupStep =
      '''
      - name: Setup Bloc Tools
        if: inputs.has_bloc_lint
        run: dart pub global activate bloc_tools $_blocToolsVersion
''';

  static const _staticBlocLintStep = r'''
      - name: Bloc Lint
        if: inputs.has_bloc_lint
        working-directory: ${{ inputs.package_path }}
        run: bloc lint .
''';

  // ── Dynamic (affected_packages + matrix) ─────────────────────────

  String _buildDynamicYaml(
    RepositoryDescription repository, {
    required String? codecovTokenSecret,
    required bool emitRequiredJob,
  }) {
    final hasDart = repository.packages.any(
      (pkg) => !RepositoryAnalyzer.dependsOnFlutter(root: pkg.root),
    );
    final hasFlutter = repository.packages.any(
      (pkg) => RepositoryAnalyzer.dependsOnFlutter(root: pkg.root),
    );

    final buffer = StringBuffer()
      ..write('''
# Generated by shorebird_ci. Safe to edit.
# Run `shorebird_ci verify` to check for dep graph drift.
# shorebird_ci-managed: dynamic
name: Shorebird CI

$_concurrencyBlock
on:
  pull_request:
    branches:
      - main
  # Checks run on the queue's own temp branch, not the PR. Without this
  # trigger the required contexts never report there and the queue
  # ejects every PR at the timeout.
  merge_group:
    types: [checks_requested]
  push:
    branches:
      - main
  # Manual dispatch runs CI against all packages, bypassing the
  # affected-packages diff. Useful on the first push to a new repo (where
  # there's no diff base) or when you want to force a full re-check.
  workflow_dispatch:

$_readOnlyPermissionsBlock
jobs:
''');

    _writeSetupJob(buffer, hasDart: hasDart, hasFlutter: hasFlutter);

    if (hasDart) {
      _writeCiJob(
        buffer,
        jobId: 'dart_ci',
        hasBlocLint: _anyDependsOnBlocLint(
          repository.packages,
          isFlutter: false,
        ),
        outputKey: 'dart_packages',
        sdk: 'dart',
        hasCodecov: repository.hasCodecov,
        codecovTokenSecret: codecovTokenSecret,
      );
    }

    if (hasFlutter) {
      _writeCiJob(
        buffer,
        jobId: 'flutter_ci',
        hasBlocLint: _anyDependsOnBlocLint(
          repository.packages,
          isFlutter: true,
        ),
        outputKey: 'flutter_packages',
        sdk: 'flutter',
        hasCodecov: repository.hasCodecov,
        codecovTokenSecret: codecovTokenSecret,
      );
    }

    if (repository.cspellConfig != null) {
      _writeCspellJob(buffer, repository);
    }

    if (emitRequiredJob) {
      final needs = <String>[
        'setup',
        if (hasDart) 'dart_ci',
        if (hasFlutter) 'flutter_ci',
        if (repository.cspellConfig != null) 'cspell',
      ];
      _writeRequiredJob(buffer, needs);
    }

    return buffer.toString();
  }

  void _writeSetupJob(
    StringBuffer buffer, {
    required bool hasDart,
    required bool hasFlutter,
  }) {
    buffer.write('''
  setup:
    runs-on: ubuntu-latest
    outputs:
''');
    if (hasDart) {
      buffer.writeln(
        r'      dart_packages: ${{ steps.affected.outputs.dart_packages }}',
      );
    }
    if (hasFlutter) {
      buffer.writeln(
        '      flutter_packages: '
        r'${{ steps.affected.outputs.flutter_packages }}',
      );
    }

    buffer
      ..write('''
    steps:
      - uses: $checkoutAction
        with:
          submodules: recursive
          # affected_packages diffs against origin/main, which isn't in
          # the default shallow checkout. Full history is needed for the
          # diff to resolve.
          fetch-depth: 0
      - uses: $setupDartAction
''')
      ..writeln(
        '      - run: dart pub global activate shorebird_ci $packageVersion',
      )
      ..write(r'''
      # Verify first so we fail fast if CI coverage is broken and
      # don't waste time computing affected packages.
      - name: Verify CI coverage
        run: shorebird_ci verify
      - id: affected
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            echo "::notice::Manual dispatch: running CI against all packages."
            EXTRA_ARGS=--all
          else
            EXTRA_ARGS=
          fi
''');
    if (hasDart) {
      buffer.write(r'''
          DART=$(shorebird_ci affected_packages --sdk dart $EXTRA_ARGS)
          echo "dart_packages=$DART" >> $GITHUB_OUTPUT
''');
    }
    if (hasFlutter) {
      buffer.write(r'''
          FLUTTER=$(shorebird_ci affected_packages --sdk flutter $EXTRA_ARGS)
          echo "flutter_packages=$FLUTTER" >> $GITHUB_OUTPUT
''');
    }
    // Friendly notice when the diff path yields nothing, e.g. on a push
    // to main where HEAD already equals origin/main. Points users at the
    // manual-dispatch button so the green check has context.
    final emptyChecks = <String>[
      if (hasDart) r'"$DART" == "[]"',
      if (hasFlutter) r'"$FLUTTER" == "[]"',
    ].join(' && ');
    buffer
      ..write('''
          if [[ "\${{ github.event_name }}" != "workflow_dispatch" ]] && [[ $emptyChecks ]]; then
            echo "::notice::No affected packages in diff vs origin/main. Click 'Run workflow' in the Actions tab to run CI against all packages."
          fi
''')
      ..writeln();
  }

  void _writeCiJob(
    StringBuffer buffer, {
    required String jobId,
    required bool hasBlocLint,
    required String outputKey,
    required String sdk,
    required bool hasCodecov,
    required String? codecovTokenSecret,
  }) {
    final isFlutter = sdk == 'flutter';
    final executable = isFlutter ? 'flutter' : 'dart';

    buffer
      ..write(_ciJobHeader(jobId: jobId, outputKey: outputKey))
      ..write(_sdkSetupStep(isFlutter: isFlutter))
      ..write(hasBlocLint ? _blocToolsSetupStep : '')
      ..write(_installDependenciesStep(executable: executable))
      ..write(_formatAndAnalyzeSteps(executable: executable))
      ..write(hasBlocLint ? _blocLintStep : '')
      ..write(
        _testStep(
          isFlutter: isFlutter,
          hasCodecov: hasCodecov,
          executable: executable,
        ),
      );

    if (isFlutter) buffer.write(_integrationTestsStep);
    if (hasCodecov) {
      buffer.write(_codecovUploadStep(codecovTokenSecret: codecovTokenSecret));
    }

    buffer.writeln();
  }

  // The job header up through the shared `actions/checkout` step.
  String _ciJobHeader({required String jobId, required String outputKey}) {
    return '''
  $jobId:
    needs: setup
    if: needs.setup.outputs.$outputKey != '[]'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include: \${{ fromJSON(needs.setup.outputs.$outputKey) }}
    name: \${{ matrix.name }}
    defaults:
      run:
        working-directory: \${{ matrix.path }}
    steps:
      - uses: $checkoutAction
        with:
          submodules: recursive
''';
  }

  // For Flutter, use `flutter_version` from the matrix if the pubspec
  // pins an exact version; otherwise fall back to `channel: stable`.
  String _sdkSetupStep({required bool isFlutter}) {
    if (!isFlutter) return '      - uses: $setupDartAction\n';
    return '''
      - name: Setup Flutter
        uses: $flutterAction
        with:
          flutter-version: \${{ matrix.flutter_version || '' }}
          channel: \${{ matrix.flutter_version && '' || 'stable' }}
''';
  }

  static const _blocToolsSetupStep =
      '''
      - name: Setup Bloc Tools
        if: matrix.has_bloc_lint == true
        run: dart pub global activate bloc_tools $_blocToolsVersion
''';

  String _installDependenciesStep({required String executable}) {
    return '''
      - name: Install Dependencies
        run: |
          $executable pub get --no-example
          for sub in \${{ matrix.subpackages }}; do
            $executable pub get --no-example -C \$sub
          done
''';
  }

  String _formatAndAnalyzeSteps({required String executable}) {
    // `dart analyze` defaults `--fatal-warnings` to on, so passing it is a
    // no-op today. Emitting it explicitly documents intent and keeps the
    // generated workflow correct if the SDK default ever flips.
    // `flutter analyze` already defaults `--fatal-warnings` to on with no
    // CLI flag, so it doesn't need the same treatment.
    final analyzeCmd = executable == 'dart'
        ? 'dart analyze --fatal-warnings .'
        : '$executable analyze .';
    return '''
      - run: dart format --set-exit-if-changed .
      - run: $analyzeCmd
''';
  }

  static const _blocLintStep = '''
      - name: Bloc Lint
        if: matrix.has_bloc_lint == true
        run: bloc lint .
''';

  String _testStep({
    required bool isFlutter,
    required bool hasCodecov,
    required String executable,
  }) {
    if (!hasCodecov) return '      - run: $executable test\n';
    if (isFlutter) return '      - run: flutter test --coverage\n';
    return r'''
      - name: Run Tests
        # Pinned until https://github.com/dart-lang/tools/issues/2667 is fixed.
        run: |
          dart pub global activate coverage 1.15.1 && \
          dart test --coverage=coverage && \
          dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --check-ignore
''';
  }

  static const _integrationTestsStep = '''
      - name: Integration Tests
        if: matrix.has_integration_tests == true
        run: flutter test integration_test
''';

  String _codecovUploadStep({required String? codecovTokenSecret}) {
    return '''
      - uses: $codecovAction
        with:
          flags: \${{ matrix.name }}
${_codecovTokenLine(codecovTokenSecret)}''';
  }

  /// Emits the `token:` line for a codecov-action `with:` block, or the
  /// empty string when no token secret is configured. Indented 10 spaces
  /// to match `flags:` peers in both static and dynamic templates.
  String _codecovTokenLine(String? secret) {
    if (secret == null || secret.isEmpty) return '';
    return '          token: \${{ secrets.$secret }}\n';
  }

  void _writeCspellJob(StringBuffer buffer, RepositoryDescription repository) {
    final configPath = posixRelative(
      repository.cspellConfig!.path,
      from: repository.root.path,
    );
    buffer
      ..write('''
  cspell:
    name: CSpell
    runs-on: ubuntu-latest
    # npx installs cspell's dependencies unpinned, so the job gets a
    # read-only token and checkout doesn't leave it in .git/config.
    permissions:
      contents: read
    steps:
      - uses: $checkoutAction
        with:
          submodules: recursive
          persist-credentials: false
      - run: npx --yes cspell@$_cspellVersion --config $configPath --no-progress "**"
''')
      ..writeln();
  }

  /// Emits an aggregator job that depends on every other job in the
  /// workflow. Designed as the single check to require in branch
  /// protection: per-package jobs only run on touched paths, so we
  /// need a job that succeeds when its dependencies are either
  /// `success` or `skipped`, and fails on `failure` or `cancelled`.
  ///
  /// `!cancelled()`, not `always()`: a superseded PR run is cancelled by
  /// the workflow's `concurrency` block, and `always()` would keep this job
  /// alive through that and report `required` red on the stale commit. A
  /// skipped required check reports success, the right answer for a run
  /// nothing is waiting on.
  void _writeRequiredJob(StringBuffer buffer, List<String> needs) {
    buffer
      ..writeln('  required:')
      ..writeln('    name: required')
      ..writeln(r'    if: ${{ !cancelled() }}')
      ..writeln('    needs:');
    for (final need in needs) {
      buffer.writeln('      - $need');
    }
    buffer
      ..write(r'''
    runs-on: ubuntu-latest
    steps:
      - name: Check required jobs
        run: |
          if [[ "${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') }}" == "true" ]]; then
            echo "One or more required jobs failed or were cancelled."
            exit 1
          fi
          echo "All required jobs passed (or were skipped because nothing changed)."
''')
      ..writeln();
  }
}

/// The bloc_tools release `bloc lint` runs from. Only the package itself
/// is pinned: pub resolves its dependencies (bloc_lint among them) fresh
/// on each activate. Neither `generate` nor Dependabot bumps it; edit it
/// here.
const _blocToolsVersion = '0.1.0-dev.25';

/// The cspell release the `cspell` job runs with `ubuntu-latest`'s own
/// Node.js. As with [_blocToolsVersion], npx resolves its dependencies
/// (the dictionaries among them) fresh on each run, and it's bumped by
/// editing it here.
const _cspellVersion = '10.4.0';

/// Emitted ahead of `on:` in the main workflow.
const _concurrencyBlock = r'''
# A new push to a PR cancels that PR's run still going on the older head.
# Other events (push to main, merge_group) group by run id, so they never
# cancel or queue behind each other.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: true
''';

/// Sets the workflow's `GITHUB_TOKEN` to read-only, whatever the repo's
/// default is: pub and test steps run third-party code. Reusable workflows
/// carry this too, so they stay read-only when a hand-written caller grants
/// more. A job that needs more declares its own `permissions:`, and a job in
/// a reusable workflow can't exceed what the calling job grants.
const _readOnlyPermissionsBlock = '''
permissions:
  contents: read
''';
