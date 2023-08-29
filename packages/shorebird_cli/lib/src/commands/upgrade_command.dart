import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';

/// {@template upgrade_command}
/// `shorebird upgrade`
/// A command which upgrades your copy of Shorebird.
/// {@endtemplate}
class UpgradeCommand extends ShorebirdCommand {
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

    late final String currentVersion;
    try {
      currentVersion = await shorebirdVersion.fetchCurrentGitHash();
    } on ProcessException catch (error) {
      updateCheckProgress.fail();
      logger.err('Fetching current version failed: ${error.message}');
      return ExitCode.software.code;
    }

    late final String latestVersion;
    try {
      latestVersion = await shorebirdVersion.fetchLatestGitHash();
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
      await shorebirdVersion.attemptReset(revision: latestVersion);
    } on ProcessException catch (error) {
      updateProgress.fail();
      logger.err('Updating failed: ${error.message}');
      return ExitCode.software.code;
    }

    updateProgress.complete('Updated successfully.');

    return ExitCode.success.code;
  }
}
