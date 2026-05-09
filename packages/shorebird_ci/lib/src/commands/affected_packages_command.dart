import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/affected_packages.dart';
import 'package:shorebird_ci/src/commands/repo_root_option.dart';

/// Lists packages affected by changes between two git refs.
///
/// Outputs a JSON array of objects designed to be consumed by GitHub
/// Actions `fromJSON()` in a `matrix.include` strategy. Each entry
/// has this shape:
///
/// ```json
/// {
///   "name": "foo",
///   "path": "packages/foo",
///   "sdk": "dart",
///   "flutter_version": "",
///   "has_bloc_lint": false,
///   "has_integration_tests": false,
///   "subpackages": "example example/nested"
/// }
/// ```
class AffectedPackagesCommand extends Command<int> with RepoRootOption {
  /// Creates an [AffectedPackagesCommand].
  AffectedPackagesCommand() {
    addRepoRootOption();
    argParser
      ..addOption(
        'base',
        help: 'Base git ref to compare against.',
        defaultsTo: 'origin/main',
      )
      ..addOption(
        'head',
        help: 'Head git ref to compare.',
        defaultsTo: 'HEAD',
      )
      ..addOption(
        'sdk',
        help: 'Filter by SDK type.',
        allowed: ['dart', 'flutter'],
      )
      ..addFlag(
        'all',
        help: 'List all packages, not just affected ones.',
      );
  }

  @override
  String get name => 'affected_packages';

  @override
  String get description => 'List packages affected by changes';

  @override
  Future<int> run() async {
    final result = affectedPackagesMetadata(
      repoRoot: Directory(repoRoot),
      baseRef: argResults!['base'] as String,
      headRef: argResults!['head'] as String,
      sdkFilter: argResults!['sdk'] as String?,
      all: argResults!.flag('all'),
    );

    if (result.isEmpty) {
      // Distinguish "no packages in repo" from "no affected packages".
      // We can't tell from here without re-analyzing, so just output [].
      stdout.writeln('[]');
      return 0;
    }

    stdout.writeln(jsonEncode(result));
    return 0;
  }
}
