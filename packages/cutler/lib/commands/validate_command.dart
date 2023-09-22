import 'package:cutler/checkout.dart';
import 'package:cutler/commands/base.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

/// Validate that a Shorebird release is consistent with its Flutter release.
class ValidateCommand extends CutlerCommand {
  /// Constructs a new [ValidateCommand].
  ValidateCommand();
  @override
  final name = 'validate';
  @override
  final description =
      'Validate that a Shorebird release is consistent with its Flutter '
      'release.';

  @override
  int run() {
    checkouts = Checkouts(config.checkoutsRoot);

    final flutterVersionName = argResults!.rest.first;

    // Given a specific Flutter version code:
    logger.info('Validating $flutterVersionName');

    // Check that our flutter fork has the expected tag.
    final origin =
        checkouts.flutter.remoteTag(tag: flutterVersionName, remote: 'origin');
    final upstream = checkouts.flutter
        .remoteTag(tag: flutterVersionName, remote: 'upstream');
    if (origin != upstream) {
      logger.err(
        'Flutter release tag $origin does not match upstream $upstream',
      );
      return ExitCode.usage.code;
    } else {
      logger.info('Flutter release tag $origin matches upstream $upstream');
    }

    // Check that the engine has the expected tag?

    final forkpoint = getFlutterVersions(checkouts, flutterVersionName);

    final releaseBranch = 'flutter_release/$flutterVersionName';
    // Check for flutter_release/$version in all of our forks
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
      logger.info('Found $remote for $repo');

      // Check that the versions at flutter_release/$version include the
      // expected flutter forkpoint hash.
      final forkpointVersion = forkpoint[repo];
      if (!checkout.isAncestor(
        ancestor: forkpointVersion.hash,
        descendant: remote.hash,
      )) {
        logger.err(
          'Release branch $releaseBranch for $repo does not include '
          'forkpoint $forkpointVersion',
        );
      }
    }

    return ExitCode.success.code;
  }
}
