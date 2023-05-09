import 'package:shorebird_cli/src/shorebird_process.dart';

const String _unknownFrameworkVersion = '0.0.0-unknown';

class GitTagVersion {
  const GitTagVersion({
    this.x,
    this.y,
    this.z,
    this.hotfix,
    this.devVersion,
    this.devPatch,
    this.commits,
    this.hash,
    this.gitTag,
  });
  const GitTagVersion.unknown()
      : x = null,
        y = null,
        z = null,
        hotfix = null,
        commits = 0,
        devVersion = null,
        devPatch = null,
        hash = '',
        gitTag = '';

  /// The X in vX.Y.Z.
  final int? x;

  /// The Y in vX.Y.Z.
  final int? y;

  /// The Z in vX.Y.Z.
  final int? z;

  /// the F in vX.Y.Z+hotfix.F.
  final int? hotfix;

  /// Number of commits since the vX.Y.Z tag.
  final int? commits;

  /// The git hash (or an abbreviation thereof) for this commit.
  final String? hash;

  /// The N in X.Y.Z-dev.N.M.
  final int? devVersion;

  /// The M in X.Y.Z-dev.N.M.
  final int? devPatch;

  /// The git tag that is this version's closest ancestor.
  final String? gitTag;

  static GitTagVersion determine(
    ShorebirdProcess process, {
    String? workingDirectory,
    bool fetchTags = false,
    String gitRef = 'HEAD',
  }) {
    if (fetchTags) {
      final channel = (process
              .runSync(
                'git',
                ['rev-parse', '--abbrev-ref', 'HEAD'],
                workingDirectory: workingDirectory,
              )
              .stdout as String)
          .trim();
      if (channel == 'dev' || channel == 'beta' || channel == 'stable') {
        // 'Skipping request to fetchTags - on well known channel $channel.'
      } else {
        const shorebirdGit = 'https://github.com/shorebirdtech/shorebird.git';
        process.runSync(
          'git',
          ['fetch', shorebirdGit, '--tags', '-f'],
          workingDirectory: workingDirectory,
        );
      }
    }

    // find all tags attached to the given [gitRef]
    final tags = (process
            .runSync(
              'git',
              ['tag', '--points-at', gitRef],
              workingDirectory: workingDirectory,
            )
            .stdout as String)
        .trim()
        .split('\n');

    // Check first for a stable tag
    final stableTagPattern = RegExp(r'^v\d+\.\d+\.\d+$');
    for (final tag in tags) {
      if (stableTagPattern.hasMatch(tag.trim())) {
        return parseVersion(tag);
      }
    }

    // Next check for a dev tag
    final devTagPattern = RegExp(r'^v\d+\.\d+\.\d+-\d+\.\d+\.pre$');
    for (final tag in tags) {
      if (devTagPattern.hasMatch(tag.trim())) {
        return parseVersion(tag);
      }
    }

    // If we're not currently on a tag, use git describe to find the most
    // recent tag and number of commits past.
    return parseVersion(
      process
          .runSync(
            'git',
            ['describe', '--match', '*.*.*', '--long', '--tags', gitRef],
            workingDirectory: workingDirectory,
          )
          .stdout as String,
    );
  }

  /// Parse a version string.
  ///
  /// The version string can either be an exact release tag (e.g. '1.2.3' for
  /// stable or 1.2.3-4.5.pre for a dev) or the output of `git describe` (e.g.
  /// for commit abc123 that is 6 commits after tag 1.2.3-4.5.pre, git would
  /// return '1.2.3-4.5.pre-6-gabc123').
  // ignore: prefer_constructors_over_static_methods
  static GitTagVersion parseVersion(String version) {
    final versionPattern = RegExp(
      r'^v(\d+)\.(\d+)\.(\d+)(-\d+\.\d+\.pre)?(?:-(\d+)-g([a-f0-9]+))?$',
    );
    final Match? match = versionPattern.firstMatch(version.trim());
    if (match == null) {
      return const GitTagVersion.unknown();
    }

    final matchGroups = match.groups(<int>[1, 2, 3, 4, 5, 6]);
    final x = matchGroups[0] == null ? null : int.tryParse(matchGroups[0]!);
    final y = matchGroups[1] == null ? null : int.tryParse(matchGroups[1]!);
    final z = matchGroups[2] == null ? null : int.tryParse(matchGroups[2]!);
    final devString = matchGroups[3];
    int? devVersion;
    int? devPatch;
    if (devString != null) {
      final Match? devMatch =
          RegExp(r'^-(\d+)\.(\d+)\.pre$').firstMatch(devString);
      final devGroups = devMatch?.groups(<int>[1, 2]);
      devVersion = devGroups?[0] == null ? null : int.tryParse(devGroups![0]!);
      devPatch = devGroups?[1] == null ? null : int.tryParse(devGroups![1]!);
    }
    // count of commits past last tagged version
    final commits = matchGroups[4] == null ? 0 : int.tryParse(matchGroups[4]!);
    final hash = matchGroups[5] ?? '';

    return GitTagVersion(
      x: x,
      y: y,
      z: z,
      devVersion: devVersion,
      devPatch: devPatch,
      commits: commits,
      hash: hash,
      gitTag: '$x.$y.$z${devString ?? ''}', // e.g. 1.2.3-4.5.pre
    );
  }

  String frameworkVersionFor(String revision) {
    if (x == null ||
        y == null ||
        z == null ||
        (hash != null && !revision.startsWith(hash!))) {
      return _unknownFrameworkVersion;
    }
    if (commits == 0 && gitTag != null) {
      return gitTag!;
    }

    return '$x.$y.${z! + 1}-0.0.pre.$commits';
  }
}
