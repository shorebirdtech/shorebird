import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';

/// {@template upgrade_command}
/// `shorebird upgrade`
/// A command which upgrades your copy of Shorebird.
/// {@endtemplate}
class UpgradeCommand extends ShorebirdCommand {
  /// {@macro upgrade_command}
  UpgradeCommand({required super.logger, super.runProcess});

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
      currentVersion = await fetchCurrentVersion(
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      updateCheckProgress.fail();
      logger.err('Fetching current version failed: ${error.message}');
      return ExitCode.software.code;
    }

    late final String latestVersion;
    try {
      latestVersion = await fetchLatestVersion(
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

    updateProgress.complete('Updated successfully.');

    return ExitCode.success.code;
  }

  /// Returns the remote HEAD shorebird version.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchLatestVersion({required String workingDirectory}) async {
    // Fetch upstream branch's commits and tags
    await runProcess(
      'git',
      ['fetch', '--tags'],
      workingDirectory: workingDirectory,
    );
    // Get the latest commit revision of the upstream
    return _gitRevParse('@{upstream}', workingDirectory: workingDirectory);
  }

  /// Returns the local HEAD shorebird version.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchCurrentVersion({
    required String workingDirectory,
  }) async {
    // Get the commit revision of HEAD
    return _gitRevParse('HEAD', workingDirectory: workingDirectory);
  }

  Future<String> _gitRevParse(
    String revision, {
    String? workingDirectory,
  }) async {
    // Get the commit revision of HEAD
    final result = await runProcess(
      'git',
      ['rev-parse', '--verify', revision],
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        ['rev-parse', '--verify', revision],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }

  /// Attempts a hard reset to the given revision.
  ///
  /// This is a reset instead of fast forward because if we are on a release
  /// branch with cherry picks, there may not be a direct fast-forward route
  /// to the next release.
  Future<void> attemptReset({
    required String newRevision,
    required String workingDirectory,
  }) async {
    final result = await runProcess(
      'git',
      ['reset', '--hard', newRevision],
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        ['reset', '--hard', newRevision],
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
