import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';

// A reference to a [Logger] instance.
final upgraderRef = create(Upgrader.new);

// The [Upgrader] instance available in the current zone.
Upgrader get upgrader => read(upgraderRef);

class Upgrader {
  Upgrader({ShorebirdProcess? process})
      : process = process ?? ShorebirdProcess();

  final ShorebirdProcess process;

  Future<bool> isUpToDate() async {
    final workingDirectory = p.dirname(Platform.script.toFilePath());
    final currentVersion = await fetchCurrentGitHash(
      workingDirectory: workingDirectory,
    );

    final latestVersion = await _fetchLatestGitHash(
      workingDirectory: workingDirectory,
    );

    return currentVersion == latestVersion;
  }

  Future<void> upgrade() async {
    final workingDirectory = p.dirname(Platform.script.toFilePath());
    final currentVersion = await fetchCurrentGitHash(
      workingDirectory: workingDirectory,
    );
    final latestVersion = await _fetchLatestGitHash(
      workingDirectory: workingDirectory,
    );
    if (currentVersion == latestVersion) return;
    return _attemptReset(
      newRevision: latestVersion,
      workingDirectory: workingDirectory,
    );
  }

  /// Returns the remote HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> _fetchLatestGitHash({required String workingDirectory}) async {
    // Fetch upstream branch's commits and tags
    await process.run(
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
    final result = await process.run(
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
  Future<void> _attemptReset({
    required String newRevision,
    required String workingDirectory,
  }) async {
    final result = await process.run(
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
