import 'package:barbecue/barbecue.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_releases_command}
///
/// `shorebird releases list`
/// List all releases for this app.
/// {@endtemplate}
class ListReleasesCommand extends ShorebirdCommand
    with AuthLoggerMixin, ShorebirdConfigMixin {
  /// {@macro list_releases_command}
  ListReleasesCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  });

  @override
  String get name => 'list';

  @override
  String get description => 'List all releases for this app.';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    if (!hasShorebirdYaml) {
      logger.err(
        '''Shorebird is not initialized. Did you run ${lightCyan.wrap('shorebird init')}?''',
      );
      return ExitCode.config.code;
    }

    final appId = getShorebirdYaml()!.appId;

    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final List<Release> releases;
    try {
      releases = await codePushClient.getReleases(appId: appId);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info('🚀 Releases ($appId)');
    if (releases.isEmpty) {
      logger.info('(empty)');
      return ExitCode.success.code;
    }

    logger.info(releases.prettyPrint());

    return ExitCode.success.code;
  }
}

extension on List<Release> {
  String prettyPrint() {
    const cellStyle = CellStyle(
      paddingLeft: 1,
      paddingRight: 1,
      borderBottom: true,
      borderTop: true,
      borderLeft: true,
      borderRight: true,
    );
    return Table(
      cellStyle: cellStyle,
      header: const TableSection(
        rows: [
          Row(
            cells: [
              Cell('Name'),
              Cell('ID'),
            ],
          )
        ],
      ),
      body: TableSection(
        rows: [
          for (final release in this)
            Row(
              cells: [
                Cell(release.displayName ?? '(no name)'),
                Cell(release.version),
              ],
            ),
        ],
      ),
    ).render();
  }
}
