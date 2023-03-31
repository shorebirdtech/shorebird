import 'dart:io';

import 'package:shorebird_cli/src/command.dart';

mixin ShorebirdVersionMixin on ShorebirdCommand {
  /// Whether the current version of Shorebird is the latest available.
  Future<bool> isShorebirdVersionCurrent({
    required String workingDirectory,
  }) async {
    final currentVersion = await fetchCurrentGitHash(
      workingDirectory: workingDirectory,
    );

    final latestVersion = await fetchLatestGitHash(
      workingDirectory: workingDirectory,
    );

    return currentVersion == latestVersion;
  }

  /// Returns the remote HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchLatestGitHash({required String workingDirectory}) async {
    // Fetch upstream branch's commits and tags
    await runProcess(
      'git',
      ['fetch', '--tags'],
      workingDirectory: workingDirectory,
    );
    // Get the latest commit revision of the upstream
    return _gitRevParse('@{upstream}', workingDirectory: workingDirectory);
  }

  /// Returns the local HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchCurrentGitHash({
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
