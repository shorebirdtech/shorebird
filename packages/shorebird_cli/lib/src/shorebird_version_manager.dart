import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/process.dart';

/// A reference to a [ShorebirdVersionManager] instance.
final shorebirdVersionManagerRef = create(ShorebirdVersionManager.new);

/// The [ShorebirdVersionManager] instance available in the current zone.
ShorebirdVersionManager get shorebirdVersionManager =>
    read(shorebirdVersionManagerRef);

/// {@template shorebird_version_manager}
/// Provides information about installed and available versions of Shorebird.
/// {@endtemplate}
class ShorebirdVersionManager {
  String get _workingDirectory => p.dirname(Platform.script.toFilePath());

  /// Whether the current version of Shorebird is the latest available.
  Future<bool> isShorebirdVersionCurrent() async {
    final currentVersion = await fetchCurrentGitHash();

    final latestVersion = await fetchLatestGitHash();

    return currentVersion == latestVersion;
  }

  /// Returns the remote HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchLatestGitHash() async {
    // Fetch upstream branch's commits and tags
    await process.run(
      'git',
      ['fetch', '--tags'],
      workingDirectory: _workingDirectory,
    );
    // Get the latest commit revision of the upstream
    return _gitRevParse('@{upstream}');
  }

  /// Returns the local HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchCurrentGitHash() async {
    // Get the commit revision of HEAD
    return _gitRevParse('HEAD');
  }

  Future<String> _gitRevParse(String revision) async {
    // Get the commit revision of HEAD
    final result = await process.run(
      'git',
      ['rev-parse', '--verify', revision],
      workingDirectory: _workingDirectory,
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
  }) async {
    final result = await process.run(
      'git',
      ['reset', '--hard', newRevision],
      workingDirectory: _workingDirectory,
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
