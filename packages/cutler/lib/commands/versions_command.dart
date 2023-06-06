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
        print('No version hash provided, using Shorebird `origin/stable`.');
        hash = 'origin/stable';
      } else {
        print('No version hash provided, using Flutter `upstream/stable`.');
        hash = 'upstream/stable';
      }
    } else {
      hash = argResults!.rest.first;
    }

    if (config.doUpdate) {
      print('Updating checkouts (use --no-update to skip)');
      for (final repo in Repo.values) {
        print('Updating ${repo.name}...');
        repo.fetchAll();
      }
    }

    late final String flutterHash;
    if (isShorebird) {
      final shorebirdFlutter =
          Repo.shorebird.contentsAtPath(hash, 'bin/internal/flutter.version');
      final shorebird = getFlutterVersions(shorebirdFlutter);
      logger.info('Shorebird $hash:');
      printVersions(shorebird, indent: 2);
      final flutterForkpoint =
          Repo.flutter.getForkPoint(shorebird.flutter.hash);
      flutterHash = flutterForkpoint.hash;
    } else {
      flutterHash = hash;
    }

    final flutterVersions = getFlutterVersions(flutterHash);
    logger.info('Flutter $flutterHash:');
    printVersions(flutterVersions, indent: 2);

    return ExitCode.success.code;
  }
}
