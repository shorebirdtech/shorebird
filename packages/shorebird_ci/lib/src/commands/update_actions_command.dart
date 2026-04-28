import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shorebird_ci/src/action_versions.dart';

/// Updates GitHub Actions `uses:` versions to the current latest major
/// in one or more workflow files.
///
/// Scans each workflow file for `uses: owner/repo@vN` references,
/// queries GitHub's API for the latest major version, and rewrites the
/// file in place. Works on any workflow file, not just ones generated
/// by `shorebird_ci`.
class UpdateActionsCommand extends Command<int> {
  /// Creates an [UpdateActionsCommand]. The optional [resolveLatestMajor]
  /// is exposed for tests so they don't have to hit the live GitHub API.
  UpdateActionsCommand({LatestMajorResolver? resolveLatestMajor})
    : _resolveLatestMajor = resolveLatestMajor {
    argParser.addOption(
      'workflow-dir',
      help: 'Directory containing workflow YAML files to update.',
      defaultsTo: '.github/workflows',
    );
  }

  final LatestMajorResolver? _resolveLatestMajor;

  @override
  String get name => 'update_actions';

  @override
  String get description => 'Update GitHub Actions versions in workflow files';

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
        resolveLatestMajor: _resolveLatestMajor,
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
