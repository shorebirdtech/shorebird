import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_releases_command}
/// Lists all releases for the current app.
/// {@endtemplate}
class ListReleasesCommand extends ShorebirdCommand {
  /// {@macro list_releases_command}
  ListReleasesCommand() {
    argParser
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The app flavor to list releases for.',
      )
      ..addOption(
        'platform',
        allowed: ReleasePlatform.values.map((e) => e.name),
        allowedHelp: {
          for (final p in ReleasePlatform.values) p.name: p.displayName,
        },
        help: 'Only show releases for the specified platform.',
      )
      ..addFlag(
        'plain',
        help: 'Output only release versions, one per line.',
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all releases for the current app';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);
    final plain = results['plain'] as bool;
    final platformName = results['platform'] as String?;
    final platform = platformName != null
        ? ReleasePlatform.values.byName(platformName)
        : null;

    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final filtered = platform != null
        ? releases
              .where((r) => r.platformStatuses.containsKey(platform))
              .toList()
        : releases;

    if (filtered.isEmpty) {
      if (!plain) logger.info('No releases found');
      return ExitCode.success.code;
    }

    final sorted = filtered.sortedBy((r) => r.createdAt).reversed.toList();

    if (plain) {
      for (final release in sorted) {
        logger.info(release.version);
      }
      return ExitCode.success.code;
    }

    logger.info('');

    for (final release in sorted) {
      final platforms = release.platformStatuses.entries
          .map((e) => '${e.key.displayName}: ${e.value.name}')
          .join(', ');

      final date = formatReleaseDate(release.createdAt);
      final version = release.version;
      final platformInfo = platforms.isNotEmpty ? '  [$platforms]' : '';

      logger.info('  $version  ($date)$platformInfo');
    }

    logger
      ..info('')
      ..info('${sorted.length} release(s) total');

    return ExitCode.success.code;
  }
}
