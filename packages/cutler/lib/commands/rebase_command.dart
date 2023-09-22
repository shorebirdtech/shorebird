import 'package:cutler/checkout.dart';
import 'package:cutler/commands/base.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

/// This isn't truly a VersionSet since it may not be a consistent
/// set of versions built into a Flutter release, rather it's just whatever
/// our current HEAD is across our fork repos.
VersionSet getHeadVersions(Checkouts checkouts, String forkBranch) {
  return VersionSet(
    engine: checkouts.engine.versionFrom(forkBranch),
    flutter: checkouts.flutter.versionFrom(forkBranch),
    buildroot: checkouts.buildroot.versionFrom(forkBranch),
    dart: checkouts.dart.versionFrom(forkBranch),
  );
}

/// Holds the state about a rebase operation.
class RebaseContext {
  /// Constructs a new [RebaseContext].
  RebaseContext(this.upstream, this.forkpoint, this.dev, this.devBranch);

  /// The VersionSet of the upstream Flutter we're rebasing to.
  final VersionSet upstream;

  /// The VersionSet of the Flutter forkpoint we're rebasing from.
  final VersionSet forkpoint;

  /// The VersionSet of the current HEAD of our fork.
  final VersionSet dev;

  /// The name of the branches we're rebasing.
  // FIXME(eseidel): This should move onto Repo.
  final String devBranch;

  /// Returns the fully qualified branch name for `shorebird/dev`.
  String get fullyQualifiedBranch => 'origin/$devBranch';

  /// Print the commands needed to rebase `shorebird/dev` to a new revision.
  void printRebase(Repo repo) {
    final path = repo.path;
    final upstreamRef = upstream[repo].ref;
    final forkpointRef = forkpoint[repo].ref;
    if (upstreamRef == forkpointRef) {
      logger
        ..info('# ${repo.name} is already at $upstreamRef')
        ..info('');
      return;
    }
    logger
      ..info('# ${repo.name}')
      ..info('git -C $path fetch --all --tags')
      ..info('git -C $path rebase --onto $upstreamRef '
          '$forkpointRef $fullyQualifiedBranch')
      ..info('# Handle conflicts');
  }

  /// Returns true if we need to push `shorebird/dev` to a new revision.
  bool needsPush(Repo repo) {
    // Only need to push if we did a rebase (or we changed a dependency).
    if (upstream[repo].ref != forkpoint[repo].ref) {
      return true;
    }
    return repo.dependencies.any(needsPush);
  }

  /// Execute the rebase operation.
  void printCommands() {
    // Print the commands needed to rebase
    printRebase(Repo.buildroot);
    printRebase(Repo.dart);
    printRebase(Repo.engine);
    printRebase(Repo.flutter);

    final flutterVersionName = upstream.flutter.aliases.first;

    if (needsPush(Repo.buildroot)) {
      // If this changes it will inevitably have conflicts to resolve anyway.
      logger.warn('Need to update buildroot version.');
    }
    if (needsPush(Repo.dart)) {
      // If this changes it will inevitably have conflicts to resolve anyway.
      logger.warn('Need to update dart version.');
    }
    if (needsPush(Repo.engine)) {
      final versionFilePath =
          p.join(Repo.flutter.path, Paths.flutterEngineVersion.path);
      logger
        ..info('git -C ${Repo.engine.path} rev-parse HEAD > $versionFilePath')
        ..info(
          'git -C ${Repo.flutter.path} commit -a '
          '-m "Update engine for $flutterVersionName"',
        )
        ..info('');
    }
    if (needsPush(Repo.flutter)) {
      final versionFilePath =
          p.join(Repo.shorebird.path, Paths.shorebirdFlutterVersion.path);
      logger
        ..info('git -C ${Repo.flutter.path} rev-parse HEAD > $versionFilePath')
        ..info(
          'git -C ${Repo.shorebird.path} commit -a '
          '-m "Update flutter for $flutterVersionName"',
        )
        ..info('');
    }

    final forks = [
      Repo.buildroot,
      Repo.dart,
      Repo.engine,
      Repo.flutter,
    ];
    for (final repo in forks) {
      if (needsPush(repo)) {
        final path = repo.path;
        final releaseBranch = 'flutter_release/$flutterVersionName';
        logger
          ..info('git -C $path push origin -f HEAD:$devBranch')
          ..info('git -C $path push --tags')
          ..info('git -C $path push origin -f $devBranch:$releaseBranch')
          ..info('');
      }
    }

    logger
      ..info('# Trigger build_engine action on GHA before pushing shorebird')
      // We just push `main` for Shorebird, since we don't have a `dev` branch.
      ..info('git -C ${Repo.shorebird.path} push');
  }
}

/// Print the versions a given Shorebird or Flutter hash depends on.
class RebaseCommand extends CutlerCommand {
  /// Constructs a new [RebaseCommand].
  RebaseCommand();
  @override
  final name = 'rebase';
  @override
  final description =
      'Print the commands needed to rebase `shorebird/dev` to a new revision.';

  @override
  int run() {
    checkouts = Checkouts(config.checkoutsRoot);
    updateReposIfNeeded(config);

    // Figure out our current versions, use `shorebird/dev` as our main branch
    // This isn't necessarily a self-consistent set of versions.
    const devBranch = 'shorebird/dev';
    final dev = getHeadVersions(checkouts, 'origin/$devBranch');
    printVersions(checkouts, dev);

    // Check if the VersionSet described by our Flutter fork actually matches
    // what our HEAD is in our `shorebird/dev` branches.  This check isn't
    // necessary, but seems like a good sanity check to make sure that we're
    // not surprised by this script including new commits in its resulting
    // VersionSet which were not previously included.
    final flutterVersions = getFlutterVersions(checkouts, dev.flutter.hash);
    if (flutterVersions != dev) {
      logger.warn('shorebirdtech/flutter:HEAD version set does not match '
          'the latest `$devBranch` version set, this means this script '
          'will include new commits in its resulting VersionSet which were '
          'not previously included in the Flutter described by '
          'shorebirdtech/flutter:HEAD.');
      printVersions(checkouts, flutterVersions);
    }

    // Compute the forkpoint of our `shorebird/dev` branches.  This is done
    // based only on our Flutter fork.  Another way to do this might be
    // to walk backwards from `shorebird/dev` until we find a commit which
    // was not authored by a Shorebird committer.
    // We can't just compare
    // `shorebird/dev` to `upstream/stable` because `upstream/stable` may
    // not be based on the same branch, since `stable` for Flutter is branched
    // and updated on the branch, rather than being a tag on main.
    final flutterForkpoint = flutter.getForkPoint(dev.flutter.hash);
    final flutterHash = flutterForkpoint.hash;
    final forkpoint = getFlutterVersions(checkouts, flutterHash);
    logger.info('Forkpoint:');
    printVersions(checkouts, forkpoint);

    // Figure out the versions we want to rebase to match upstream.
    const upstreamBranch = 'upstream/stable';
    final upstream = getFlutterVersions(checkouts, upstreamBranch);
    if (forkpoint == upstream) {
      logger.info('forkpoint is current with $upstreamBranch');
      return ExitCode.success.code;
    } else {
      logger.info('forkpoint is behind $upstreamBranch');
      printVersions(checkouts, upstream);
    }

    RebaseContext(upstream, forkpoint, dev, devBranch).printCommands();

    return ExitCode.success.code;
  }
}
