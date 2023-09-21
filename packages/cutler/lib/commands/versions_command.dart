import 'package:cutler/checkout.dart';
import 'package:cutler/commands/base.dart';
import 'package:cutler/logger.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

/// Print the versions a given Shorebird or Flutter hash depends on.
class VersionsCommand extends CutlerCommand {
  /// Constructs a new [VersionsCommand].
  VersionsCommand() {
    argParser.addOption(
      'repo',
      abbr: 'r',
      help: 'Repo the hash belongs to.',
      allowed: ['shorebird', 'flutter'],
      defaultsTo: 'shorebird',
    );
  }
  @override
  final name = 'versions';
  @override
  final description =
      'Print the versions a Shorebird or Flutter release hash depends on.';

  @override
  int run() {
    checkouts = Checkouts(config.checkoutsRoot);

    final repoName = argResults!['repo'] as String;
    final repo = Repo.values.firstWhere((r) => r.name == repoName);
    final isShorebird = repo.name == 'shorebird';
    late final String hash;
    if (argResults!.rest.isEmpty) {
      hash = isShorebird ? 'origin/stable' : 'upstream/stable';
    } else {
      hash = argResults!.rest.first;
    }

    updateReposIfNeeded(config);

    if (!isShorebird) {
      final flutterVersions = getFlutterVersions(checkouts, hash);
      logger.info('Flutter $hash:');
      printVersions(checkouts, flutterVersions, indent: 2);
      return ExitCode.success.code;
    }

    final shorebirdFlutter =
        shorebird.contentsAtPath(hash, 'bin/internal/flutter.version');
    final shorebirdVersions = getFlutterVersions(checkouts, shorebirdFlutter);
    final flutterForkpoint =
        flutter.getForkPoint(shorebirdVersions.flutter.hash);
    final flutterHash = flutterForkpoint.hash;
    final flutterVersions = getFlutterVersions(checkouts, flutterHash);

    logger.info('Shorebird @ $hash');
    printVersions(
      checkouts,
      shorebirdVersions,
      indent: 2,
      upstream: flutterVersions,
    );
    logger.info('Upstream');
    printVersions(
      checkouts,
      flutterVersions,
      indent: 2,
      trailingNewline: false,
    );

    return ExitCode.success.code;
  }
}
