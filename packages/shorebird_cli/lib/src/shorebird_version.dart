import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/executables/executables.dart';

/// A reference to a [ShorebirdVersion] instance.
final shorebirdVersionRef = create(ShorebirdVersion.new);

/// The [ShorebirdVersion] instance available in the current zone.
ShorebirdVersion get shorebirdVersion => read(shorebirdVersionRef);

/// {@template shorebird_version}
/// Provides information about installed and available versions of Shorebird.
/// {@endtemplate}
class ShorebirdVersion {
  String get _workingDirectory => p.dirname(Platform.script.toFilePath());

  /// Whether the current version of Shorebird is the latest available.
  Future<bool> isLatest() async {
    final currentVersion = await fetchCurrentGitHash();
    final latestVersion = await fetchLatestGitHash();

    return currentVersion == latestVersion;
  }

  /// Returns the remote HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchLatestGitHash() async {
    // Fetch upstream branch's commits and tags
    await git.fetch(directory: _workingDirectory, args: ['--tags']);
    // Get the latest commit revision of the upstream
    return git.revParse(revision: '@{upstream}', directory: _workingDirectory);
  }

  /// Returns the local HEAD shorebird hash.
  ///
  /// Exits if HEAD isn't pointing to a branch, or there is no upstream.
  Future<String> fetchCurrentGitHash() async {
    // Get the commit revision of HEAD
    return git.revParse(revision: 'HEAD', directory: _workingDirectory);
  }

  /// Attempts a hard reset to the given revision.
  ///
  /// This is a reset instead of fast forward because if we are on a release
  /// branch with cherry picks, there may not be a direct fast-forward route
  /// to the next release.
  Future<void> attemptReset({required String revision}) async {
    return git.reset(
      revision: revision,
      directory: _workingDirectory,
      args: ['--hard'],
    );
  }
}
