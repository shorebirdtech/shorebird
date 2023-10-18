import 'package:barbecue/barbecue.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_releases_command}
/// `shorebird releases list`
/// List all releases for this app.
/// {@endtemplate}
class ListReleasesCommand extends ShorebirdCommand {
  /// {@macro list_releases_command}
  ListReleasesCommand() {
    argParser.addOption(
      'flavor',
      help: 'The product flavor to use when listing releases.',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all releases for this app.';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

    final List<Release> releases;
    try {
      releases = await codePushClientWrapper.codePushClient.getReleases(
        appId: appId,
      );
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
              Cell('Version'),
              Cell('Name'),
            ],
          )
        ],
      ),
      body: TableSection(
        rows: [
          for (final release in this)
            Row(
              cells: [
                Cell(release.version),
                Cell(release.displayName ?? '--'),
              ],
            ),
        ],
      ),
    ).render();
  }
}
