import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

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
    // Dependabot pushed branches with the same name breaking all clients
    // and requiring a prune to repair them.
    await git.remote(directory: _workingDirectory, args: ['prune', 'origin']);
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

  /// Whether this checkout of shorebird has an upstream branch to compare
  /// against. A checkout of a commit or tag (a detached HEAD), or a local
  /// branch with no upstream, has nothing newer to compare it to.
  ///
  /// Throws a [ProcessException] if git fails for another reason.
  Future<bool> hasUpstream() async {
    try {
      await git.git([
        'rev-parse',
        '-q',
        '--verify',
        '@{upstream}',
      ], workingDirectory: _workingDirectory);
      return true;
    } on ProcessException catch (e) {
      // `rev-parse -q --verify` exits 1 when the ref doesn't resolve and 128
      // for other errors.
      if (e.errorCode == 1) return false;
      rethrow;
    }
  }

  /// Tells the user how to get back on the latest Shorebird when
  /// [hasUpstream] is false.
  String get noUpstreamMessage {
    final root = shorebirdEnv.shorebirdRoot.path;
    return '''
Shorebird at $root is not on a branch that receives updates.
To get the latest Shorebird, run:
  git -C $root checkout stable
  shorebird upgrade''';
  }

  /// Whether the current version of shorebird is tracking the stable branch. If
  /// we are not tracking stable, we should not check for newer versions of
  /// shorebird or try to auto-update.
  Future<bool> isTrackingStable() async {
    return (await git.currentBranch(directory: Directory(_workingDirectory))) ==
        'stable';
  }
}
