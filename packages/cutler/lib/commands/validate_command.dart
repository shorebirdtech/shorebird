import 'package:cutler/checkout.dart';
import 'package:cutler/commands/base.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';
import 'package:version/version.dart' as semver;

/// Check that a tag matches its upstream.
bool ensureTagMatch(Checkout checkout, String tag) {
  final origin = checkout.remoteTag(tag: tag, remote: 'origin');
  final upstream = checkout.remoteTag(tag: tag, remote: 'upstream');
  final paddedName = checkout.name.padRight(10);
  if (origin != upstream) {
    logger.err('❌ $paddedName tag $origin does not match upstream $upstream');
    return false;
  }
  logger.info('✅ $paddedName ${origin.ref} matches upstream $upstream');
  return true;
}

/// Check for a flutter_release/$[flutterVersionName] branch in all of our fork
/// repositories and that our Flutter forkpoint is included in the release
/// branch.
bool ensureReleaseBranchesIncludeForkpoint(
  Checkouts checkouts,
  String flutterVersionName,
) {
  final forkpoint = getFlutterVersions(checkouts, flutterVersionName);
  final releaseBranch = 'flutter_release/$flutterVersionName';
  final forks = [
    Repo.buildroot,
    Repo.dart,
    Repo.engine,
    Repo.flutter,
  ];
  for (final repo in forks) {
    final checkout = checkouts[repo];
    final remote =
        checkout.remoteBranch(branch: releaseBranch, remote: 'origin');
    final paddedName = checkout.name.padRight(10);

    // Check that the versions at flutter_release/$version include the
    // expected flutter forkpoint hash.
    final forkpointVersion = forkpoint[repo];
    if (!checkout.isAncestor(
      ancestor: forkpointVersion.hash,
      descendant: remote.hash,
    )) {
      logger.err(
        '❌ $paddedName $releaseBranch does not include '
        'forkpoint $forkpointVersion',
      );
      return false;
    }
    logger.info('✅ $paddedName correctly branched');
  }
  return true;
}

/// Validate that a Shorebird release for a given [flutterVersionName]
/// exists and is consistent with its Flutter release.
bool validateRelease(Checkouts checkouts, String flutterVersionName) {
  // Check that our flutter fork has the expected tag.
  if (!ensureTagMatch(checkouts.flutter, flutterVersionName)) {
    return false;
  }
  // Check that the engine has the expected tag.
  if (!ensureTagMatch(checkouts.engine, flutterVersionName)) {
    return false;
  }

  // Check for flutter_release/$version in all of our forks
  // and that our flutter forkpoint is included in the release branch.
  if (!ensureReleaseBranchesIncludeForkpoint(
    checkouts,
    flutterVersionName,
  )) {
    return false;
  }
  return true;
}

/// Return all Flutter versions that are tagged in the upstream Flutter repo.
/// Does not include pre-releases.
/// Returns in descending order (latest release first).
Iterable<String> allFlutterVersions(Checkout flutter) {
  final versionTags = flutter.remoteTags(remote: 'upstream');
  final semvers = <semver.Version>[];
  for (final tag in versionTags) {
    // e.g. refs/tags/v1.9.7-hotfix.4
    final tagName = tag.ref;
    final versionName = tagName.split('/').last;
    // ignore old versions
    if (versionName[0] != '3') {
      continue;
    }
    final version = semver.Version.parse(versionName);
    logger.info('Found flutter tag $version');
    if (version.isPreRelease) {
      continue;
    }
    semvers.add(version);
  }
  semvers.sort();
  // Default sort is ascending, we want descending so call reversed.
  return semvers.reversed.map((version) => version.toString());
}

/// Validate that a Shorebird release is consistent with its Flutter release.
class ValidateCommand extends CutlerCommand {
  /// Constructs a new [ValidateCommand].
  ValidateCommand() {
    argParser.addFlag(
      'all',
      help: 'Validate all Flutter releases.',
    );
  }
  @override
  final name = 'validate';
  @override
  final description =
      'Validate that a Shorebird release is consistent with its Flutter '
      'release.';

  @override
  int run() {
    checkouts = Checkouts(config.checkoutsRoot);

    // If they passed --all, validate all Flutter releases.
    // Otherwise, validate the versions they passed.
    final versions = argResults!['all'] as bool
        ? allFlutterVersions(checkouts.flutter)
        : argResults!.rest;

    if (versions.isEmpty) {
      logger
        ..err('No versions to validate.')
        ..info(argParser.usage);
      return ExitCode.usage.code;
    }

    for (final version in versions) {
      logger.info('Validating $version');
      if (!validateRelease(checkouts, version)) {
        return ExitCode.software.code;
      }
    }
    return ExitCode.success.code;
  }
}
