import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/commands/repo_root_option.dart';
import 'package:shorebird_ci/src/dependency_resolver.dart';
import 'package:shorebird_ci/src/flutter_version_resolver.dart';
import 'package:shorebird_ci/src/package_description.dart';
import 'package:shorebird_ci/src/repository_analyzer.dart';
import 'package:shorebird_ci/src/repository_description.dart';

/// Generates a GitHub Actions CI workflow for a Dart/Flutter repository.
class GenerateCommand extends Command<int> with RepoRootOption {
  /// Creates a [GenerateCommand].
  GenerateCommand() {
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
      );
  }

  @override
  String get name => 'generate';

  @override
  String get description => 'Generate a GitHub Actions CI workflow';

  @override
  Future<int> run() async {
    final outputPath = argResults!['output'] as String;
    final dryRun = argResults!.flag('dry-run');
    final style = argResults!['style'] as String;

    final analyzer = RepositoryAnalyzer();
    final repoDir = Directory(repoRoot);
    final repository = analyzer.analyze(
      repositoryRoot: repoDir,
    );

    if (repository.packages.isEmpty) {
      stderr.writeln('No Dart packages found in $repoRoot');
      return 1;
    }

    // Each builder returns a map of repo-relative path → file content.
    // Dynamic returns a single entry; static returns a main workflow
    // plus one or two reusable workflows.
    //
    // Action versions are emitted as the hardcoded defaults below;
    // run `shorebird_ci update_actions` to bump them.
    final files = style == 'static'
        ? _buildStaticFiles(repository, outputPath: outputPath)
        : {outputPath: _buildDynamicYaml(repository)};

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

    return 0;
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
  }) {
    final packages = repository.packages.toList()
      ..sort(
        (PackageDescription a, PackageDescription b) =>
            a.name.compareTo(b.name),
      );

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
      ),
    };
    if (hasDart) {
      files['.github/workflows/_shorebird_ci_dart.yaml'] =
          _buildDartReusableWorkflow(hasCodecov: repository.hasCodecov);
    }
    if (hasFlutter) {
      files['.github/workflows/_shorebird_ci_flutter.yaml'] =
          _buildFlutterReusableWorkflow(hasCodecov: repository.hasCodecov);
    }
    return files;
  }

  String _buildStaticMainYaml({
    required RepositoryDescription repository,
    required List<PackageDescription> packages,
  }) {
    final resolver = DependencyResolver(repository.root.path);
    final buffer = StringBuffer()
      ..write('''
# Generated by shorebird_ci --style static. Safe to edit.
# Run `shorebird_ci verify` to check for dep graph drift.
name: Shorebird CI

on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
''');

    for (final package in packages) {
      buffer.writeln(
        '      ${package.name}: '
        '\${{ steps.filter.outputs.${package.name} }}',
      );
    }

    // Verify first so we fail fast if the dorny filters below have
    // drifted from the Dart dep graph. Without this, a new package or
    // a changed `path:` dependency would silently go uncovered.
    buffer.write('''
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub global activate shorebird_ci
      - name: Verify CI coverage
        run: shorebird_ci verify
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
''');

    for (final package in packages) {
      final packageDir = p.relative(
        package.rootPath,
        from: repository.root.path,
      );
      final sortedDeps = resolver.resolve(packageDir).toList()..sort();

      buffer.writeln('            ${package.name}:');
      for (final dep in sortedDeps) {
        buffer.writeln('              - $dep/**');
      }
    }
    buffer.writeln();

    for (final package in packages) {
      final packageDir = p.relative(
        package.rootPath,
        from: repository.root.path,
      );
      final isFlutter = RepositoryAnalyzer.dependsOnFlutter(
        root: package.root,
      );
      final subpackages =
          RepositoryAnalyzer.subpackages(package: package)
              .map((sub) => p.relative(sub.rootPath, from: package.rootPath))
              .toList()
            ..sort();
      final reusable = isFlutter
          ? '_shorebird_ci_flutter.yaml'
          : '_shorebird_ci_dart.yaml';

      buffer.write('''
  ${package.name}:
    needs: changes
    if: needs.changes.outputs.${package.name} == 'true'
    uses: ./.github/workflows/$reusable
    with:
      package_name: ${package.name}
      package_path: $packageDir
      has_bloc_lint: ${RepositoryAnalyzer.dependsOnBlocLint(root: package.root)}
      subpackages: "${subpackages.join(' ')}"
''');

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

      buffer.writeln();
    }

    if (repository.cspellConfig != null) {
      _writeCspellJob(buffer, repository);
    }

    return buffer.toString();
  }

  String _buildDartReusableWorkflow({required bool hasCodecov}) {
    final testStep = hasCodecov
        ? r'''
      - name: Run Tests
        working-directory: ${{ inputs.package_path }}
        run: |
          dart pub global activate coverage && \
          dart test --coverage=coverage && \
          dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --check-ignore
      - uses: codecov/codecov-action@v5
        with:
          flags: ${{ inputs.package_name }}
          working-directory: ${{ inputs.package_path }}
'''
        : r'''
      - working-directory: ${{ inputs.package_path }}
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
      has_bloc_lint:
        required: false
        default: false
        type: boolean
      subpackages:
        required: false
        default: ""
        type: string

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: dart-lang/setup-dart@v1
      - name: Setup Bloc Tools
        if: inputs.has_bloc_lint
        uses: felangel/setup-bloc-tools@v0
      - name: Install Dependencies
        working-directory: \${{ inputs.package_path }}
        run: |
          dart pub get --no-example
          for sub in \${{ inputs.subpackages }}; do
            dart pub get --no-example -C \$sub
          done
      - working-directory: \${{ inputs.package_path }}
        run: dart format --set-exit-if-changed .
      - working-directory: \${{ inputs.package_path }}
        run: dart analyze .
      - name: Bloc Lint
        if: inputs.has_bloc_lint
        working-directory: \${{ inputs.package_path }}
        run: bloc lint .
$testStep''';
  }

  String _buildFlutterReusableWorkflow({required bool hasCodecov}) {
    final testStep = hasCodecov
        ? r'''
      - working-directory: ${{ inputs.package_path }}
        run: flutter test --coverage
      - uses: codecov/codecov-action@v5
        with:
          flags: ${{ inputs.package_name }}
          working-directory: ${{ inputs.package_path }}
'''
        : r'''
      - working-directory: ${{ inputs.package_path }}
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
      has_bloc_lint:
        required: false
        default: false
        type: boolean
      has_integration_tests:
        required: false
        default: false
        type: boolean
      subpackages:
        required: false
        default: ""
        type: string

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: \${{ inputs.flutter_version || '' }}
          channel: \${{ inputs.flutter_version && '' || 'stable' }}
      - name: Setup Bloc Tools
        if: inputs.has_bloc_lint
        uses: felangel/setup-bloc-tools@v0
      - name: Install Dependencies
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
      - name: Bloc Lint
        if: inputs.has_bloc_lint
        working-directory: \${{ inputs.package_path }}
        run: bloc lint .
$testStep      - name: Integration Tests
        if: inputs.has_integration_tests
        working-directory: \${{ inputs.package_path }}
        run: flutter test integration_test
''';
  }

  // ── Dynamic (affected_packages + matrix) ─────────────────────────

  String _buildDynamicYaml(RepositoryDescription repository) {
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

on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

jobs:
''');

    _writeSetupJob(buffer, hasDart: hasDart, hasFlutter: hasFlutter);

    if (hasDart) {
      _writeCiJob(
        buffer,
        jobId: 'dart_ci',
        outputKey: 'dart_packages',
        sdk: 'dart',
        hasCodecov: repository.hasCodecov,
      );
    }

    if (hasFlutter) {
      _writeCiJob(
        buffer,
        jobId: 'flutter_ci',
        outputKey: 'flutter_packages',
        sdk: 'flutter',
        hasCodecov: repository.hasCodecov,
      );
    }

    if (repository.cspellConfig != null) {
      _writeCspellJob(buffer, repository);
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

    buffer.write('''
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: dart-lang/setup-dart@v1
      - run: dart pub global activate shorebird_ci
      # Verify first so we fail fast if CI coverage is broken and
      # don't waste time computing affected packages.
      - name: Verify CI coverage
        run: shorebird_ci verify
      - id: affected
        run: |
''');
    if (hasDart) {
      buffer.write(r'''
          DART=$(shorebird_ci affected_packages --sdk dart)
          echo "dart_packages=$DART" >> $GITHUB_OUTPUT
''');
    }
    if (hasFlutter) {
      buffer.write(r'''
          FLUTTER=$(shorebird_ci affected_packages --sdk flutter)
          echo "flutter_packages=$FLUTTER" >> $GITHUB_OUTPUT
''');
    }
    buffer.writeln();
  }

  void _writeCiJob(
    StringBuffer buffer, {
    required String jobId,
    required String outputKey,
    required String sdk,
    required bool hasCodecov,
  }) {
    final isFlutter = sdk == 'flutter';
    final executable = isFlutter ? 'flutter' : 'dart';

    buffer
      ..write(_ciJobHeader(jobId: jobId, outputKey: outputKey))
      ..write(_sdkSetupStep(isFlutter: isFlutter))
      ..write(_blocToolsSetupStep)
      ..write(_installDependenciesStep(executable: executable))
      ..write(_formatAndAnalyzeSteps(executable: executable))
      ..write(
        _testStep(
          isFlutter: isFlutter,
          hasCodecov: hasCodecov,
          executable: executable,
        ),
      );

    if (isFlutter) buffer.write(_integrationTestsStep);
    if (hasCodecov) buffer.write(_codecovUploadStep);

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
      - uses: actions/checkout@v4
        with:
          submodules: recursive
''';
  }

  // For Flutter, use `flutter_version` from the matrix if the pubspec
  // pins an exact version; otherwise fall back to `channel: stable`.
  String _sdkSetupStep({required bool isFlutter}) {
    if (!isFlutter) return '      - uses: dart-lang/setup-dart@v1\n';
    return r'''
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ matrix.flutter_version || '' }}
          channel: ${{ matrix.flutter_version && '' || 'stable' }}
''';
  }

  static const _blocToolsSetupStep = '''
      - name: Setup Bloc Tools
        if: matrix.has_bloc_lint == true
        uses: felangel/setup-bloc-tools@v0
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
    return '''
      - run: dart format --set-exit-if-changed .
      - run: $executable analyze .
      - name: Bloc Lint
        if: matrix.has_bloc_lint == true
        run: bloc lint .
''';
  }

  String _testStep({
    required bool isFlutter,
    required bool hasCodecov,
    required String executable,
  }) {
    if (!hasCodecov) return '      - run: $executable test\n';
    if (isFlutter) return '      - run: flutter test --coverage\n';
    return r'''
      - name: Run Tests
        run: |
          dart pub global activate coverage && \
          dart test --coverage=coverage && \
          dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --check-ignore
''';
  }

  static const _integrationTestsStep = '''
      - name: Integration Tests
        if: matrix.has_integration_tests == true
        run: flutter test integration_test
''';

  static const _codecovUploadStep = r'''
      - uses: codecov/codecov-action@v5
        with:
          flags: ${{ matrix.name }}
''';

  void _writeCspellJob(
    StringBuffer buffer,
    RepositoryDescription repository,
  ) {
    final configPath = p.relative(
      repository.cspellConfig!.path,
      from: repository.root.path,
    );
    buffer
      ..write('''
  cspell:
    name: CSpell
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: streetsidesoftware/cspell-action@v6
        with:
          incremental_files_only: false
          config: $configPath
''')
      ..writeln();
  }
}
