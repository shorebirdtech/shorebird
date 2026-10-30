import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/action_versions.dart';

/// Pins GitHub Actions `uses:` references to each action's latest
/// release, by commit SHA, in one or more workflow files.
///
/// Scans each workflow file for `uses: owner/repo@vN` and
/// `uses: owner/repo@<sha> # vN.N.N` references, queries GitHub's API
/// for the latest release and its commit, and rewrites the file in place
/// as `owner/repo@<sha> # <tag>`. Works on any workflow file, not just ones generated
/// by `shorebird_ci`.
class UpdateActionsCommand extends Command<int> {
  /// Creates an [UpdateActionsCommand]. The optional [resolveLatestRelease]
  /// is exposed for tests so they don't have to hit the live GitHub API.
  UpdateActionsCommand({LatestReleaseResolver? resolveLatestRelease})
    : _resolveLatestRelease = resolveLatestRelease {
    argParser.addOption(
      'workflow-dir',
      help: 'Directory containing workflow YAML files to update.',
      defaultsTo: '.github/workflows',
    );
  }

  final LatestReleaseResolver? _resolveLatestRelease;

  @override
  String get name => 'update_actions';

  @override
  String get description =>
      'Pin GitHub Actions in workflow files to their latest releases by SHA';

  @override
  Future<int> run() async {
    final workflowDir = Directory(
      argResults!['workflow-dir'] as String,
    );
    if (!workflowDir.existsSync()) {
      stderr.writeln('No such directory: ${workflowDir.path}');
      return 1;
    }

    final files =
        workflowDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      stderr.writeln('No workflow files found in ${workflowDir.path}');
      return 0;
    }

    var updatedCount = 0;
    for (final file in files) {
      final before = file.readAsStringSync();
      final after = await updateActionVersions(
        before,
        resolveLatestRelease: _resolveLatestRelease,
      );
      if (before != after) {
        file.writeAsStringSync(after);
        stdout.writeln('Updated: ${file.path}');
        updatedCount++;
      }
    }

    stdout.writeln(
      updatedCount == 0
          ? 'All action versions are up to date.'
          : '\nUpdated $updatedCount workflow(s).',
    );
    return 0;
  }
}
