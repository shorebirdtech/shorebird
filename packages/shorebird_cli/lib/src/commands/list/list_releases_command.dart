import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/preview_command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_releases_command}
/// A command to list available releases.
/// {@endtemplate}
class ListReleasesCommand extends ShorebirdCommand {
  /// {@macro list_releases_command}
  ListReleasesCommand() {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'limit',
        help: 'Limit number of releases to be printed.',
        defaultsTo: '$_limit',
      );
  }

  static const int _limit = 10;

  @override
  String get description => 'List available releases.';

  @override
  String get name => 'list';

  /// The shorebird app ID for the current project.
  String get appId => shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

  /// The build flavor, if provided.
  late String? flavor = results['flavor'] as String?;

  /// Whether to only show the latest release for each platform.
  late int limit = int.tryParse(
        results['limit'] as String? ?? '$_limit',
      ) ??
      _limit;

  final _dateFormat = DateFormat('MM/dd/yyyy h:mm a');

  void _logKeyValue(String key, String value) {
    logger.info('  ${darkGray.wrap(key)}: $value');
  }

  void _logRelease(Release release) {
    logger.info(release.version);
    _logKeyValue('Created', _dateFormat.format(release.createdAt));
    _logKeyValue('Last Updated', _dateFormat.format(release.updatedAt));
    if (release.activePlatforms case final platforms
        when platforms.isNotEmpty) {
      final sorted = platforms.map((e) => e.displayName).sorted();
      _logKeyValue('Platforms', sorted.join(', '));
    }
  }

  @override
  Future<int> run() async {
    final releases = await codePushClientWrapper.getReleases(appId: appId);

    if (releases.isEmpty) {
      logger.info('No releases found for $appId');
      return 0;
    }

    final toDisplay = releases.take(limit).toList();

    logger
      ..info('Found ${releases.length} releases for $appId')
      ..info('Latest Releases (${toDisplay.length}):')
      ..info('');

    /// Show the most recent last
    for (final release in toDisplay.reversed) {
      _logRelease(release);
    }

    return 0;
  }
}
