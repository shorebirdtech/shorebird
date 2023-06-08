import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_version_mixin.dart';

/// {@template upgrade_command}
/// `shorebird upgrade`
/// A command which upgrades your copy of Shorebird.
/// {@endtemplate}
class UpgradeCommand extends ShorebirdCommand with ShorebirdVersionMixin {
  /// {@macro upgrade_command}
  UpgradeCommand();

  @override
  String get description => 'Upgrade your copy of Shorebird.';

  static const String commandName = 'upgrade';

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final updateCheckProgress = logger.progress('Checking for updates');
    final workingDirectory = p.dirname(Platform.script.toFilePath());

    late final String currentVersion;
    try {
      currentVersion = await fetchCurrentGitHash(
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      updateCheckProgress.fail();
      logger.err('Fetching current version failed: ${error.message}');
      return ExitCode.software.code;
    }

    late final String latestVersion;
    try {
      latestVersion = await fetchLatestGitHash(
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      updateCheckProgress.fail();
      logger.err('Checking for updates failed: ${error.message}');
      return ExitCode.software.code;
    }

    updateCheckProgress.complete('Checked for updates');

    final isUpToDate = currentVersion == latestVersion;
    if (isUpToDate) {
      logger.info('Shorebird is already at the latest version.');
      return ExitCode.success.code;
    }

    final updateProgress = logger.progress('Updating');

    try {
      await attemptReset(
        newRevision: latestVersion,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      updateProgress.fail();
      logger.err('Updating failed: ${error.message}');
      return ExitCode.software.code;
    }

    try {
      await _pruneFlutterOrigin();
    } on ProcessException catch (error) {
      updateProgress.fail();
      logger.err('Updating failed: ${error.message}');
      return ExitCode.software.code;
    }

    updateProgress.complete('Updated successfully.');

    return ExitCode.success.code;
  }

  // Intended to fix an issue caused by a change in our remote branches.
  // We deleted (origin/shorebird) and created (origin/shorebird/main)
  //
  // The error manifested at:
  // $ shorebird --version
  //   Updating Flutter...
  //   error: cannot lock ref 'refs/remotes/origin/shorebird/main': 'refs/remotes/origin/shorebird' exists; cannot create 'refs/remotes/origin/shorebird/main'
  //   From https://github.com/shorebirdtech/flutter
  //    ! [new branch]          shorebird/main -> origin/shorebird/main  (unable to update local ref)
  Future<void> _pruneFlutterOrigin() async {
    const executable = 'git';
    final args = ['remote', 'prune', 'origin'];
    final result = await process.run(
      executable,
      args,
      workingDirectory: ShorebirdEnvironment.flutterDirectory.path,
    );

    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
