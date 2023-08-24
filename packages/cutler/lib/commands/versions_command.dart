import 'package:cutler/commands/base.dart';
import 'package:cutler/config.dart';
import 'package:cutler/git_extensions.dart';
import 'package:cutler/model.dart';
import 'package:cutler/versions.dart';
import 'package:io/io.dart';

/// Print the versions a given Shorebird or Flutter hash depends on.
class VersionsCommand extends CutlerCommand {
  /// Constructs a new [VersionsCommand] with a given [logger].
  VersionsCommand({required super.logger}) {
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
    final repoName = argResults!['repo'] as String;
    final repo = Repo.values.firstWhere((r) => r.name == repoName);
    final isShorebird = repo.name == 'shorebird';
    late final String hash;
    if (argResults!.rest.isEmpty) {
      if (isShorebird) {
        hash = 'origin/stable';
      } else {
        hash = 'upstream/stable';
      }
    } else {
      hash = argResults!.rest.first;
    }

    updateReposIfNeeded(config);

    if (!isShorebird) {
      final flutterVersions = getFlutterVersions(hash);
      logger.info('Flutter $hash:');
      printVersions(flutterVersions, indent: 2);
      return ExitCode.success.code;
    }

    final shorebirdFlutter =
        Repo.shorebird.contentsAtPath(hash, 'bin/internal/flutter.version');
    final shorebird = getFlutterVersions(shorebirdFlutter);
    final flutterForkpoint = Repo.flutter.getForkPoint(shorebird.flutter.hash);
    final flutterHash = flutterForkpoint.hash;
    final flutterVersions = getFlutterVersions(flutterHash);

    logger.info('Shorebird @ $hash');
    printVersions(shorebird, indent: 2, upstream: flutterVersions);
    logger.info('\nUpstream');
    printVersions(flutterVersions, indent: 2);

    return ExitCode.success.code;
  }
}
