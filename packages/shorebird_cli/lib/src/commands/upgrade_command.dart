import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
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

  /// Name of the command, exposed for the [CommandRunner].
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
      if (!await shorebirdVersion.hasUpstream()) {
        updateCheckProgress.fail();
        logger.err(shorebirdVersion.noUpstreamMessage);
        return ExitCode.software.code;
      }
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

    // On Windows, set up the new version now (fetch its Flutter, get its
    // packages, compile it) by running it once, as `flutter upgrade` does.
    // Otherwise the next command does that setup, with its output mixed into
    // that command's.
    if (platform.isWindows) {
      final launcher = p.join(
        shorebirdEnv.shorebirdRoot.path,
        'bin',
        'shorebird.bat',
      );
      final setupExitCode = await process.stream(launcher, ['--version']);
      if (setupExitCode != ExitCode.success.code) {
        logger.err(
          'Setting up the new version failed (exit code $setupExitCode). '
          'Run `shorebird --version` to try again.',
        );
        return ExitCode.software.code;
      }
    }

    return ExitCode.success.code;
  }
}
