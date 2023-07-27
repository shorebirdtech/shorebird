import 'dart:async';

import 'package:barbecue/barbecue.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_apps_command}
///
/// `shorebird apps list`
/// List all apps using Shorebird.
/// {@endtemplate}
class ListAppsCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin {
  @override
  String get description => 'List all apps using Shorebird.';

  @override
  String get name => 'list';

  @override
  List<String> get aliases => ['ls'];

  @override
  Future<int>? run() async {
    final consoleLink = link(uri: Uri.parse('https://console.shorebird.dev'));
    logger.warn(
      '''
This command is deprecated and will be removed in a future release.
Please use $consoleLink instead.''',
    );

    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final apps = await codePushClientWrapper.getApps();

    logger.info('📱 Apps');

    if (apps.isEmpty) {
      logger.info('(empty)');
      return ExitCode.success.code;
    }

    logger.info(apps.prettyPrint());

    return ExitCode.success.code;
  }
}

extension on List<AppMetadata> {
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
              Cell('Release'),
              Cell('Patch'),
            ],
          )
        ],
      ),
      body: TableSection(
        rows: [
          for (final app in this)
            Row(
              cells: [
                Cell(app.displayName),
                Cell(app.appId),
                Cell(app.latestReleaseVersion ?? '--'),
                Cell(app.latestPatchNumber?.toString() ?? '--'),
              ],
            ),
        ],
      ),
    ).render();
  }
}
