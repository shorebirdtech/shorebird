import 'dart:async';

import 'package:barbecue/barbecue.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_collaborators_command}
/// `shorebird collaborators list`
/// List all collaborators for a Shorebird app.
/// {@endtemplate}
class ListCollaboratorsCommand extends ShorebirdCommand {
  /// {@macro list_collaborators_command}
  ListCollaboratorsCommand() {
    argParser.addOption(
      _appIdOption,
      help: 'The app id to list collaborators for.',
    );
  }

  static const String _appIdOption = 'app-id';

  @override
  String get name => 'list';

  @override
  String get description => 'List all collaborators for a Shorebird app.';

  @override
  List<String> get aliases => ['ls'];

  @override
  Future<int>? run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final appId = results[_appIdOption] as String? ??
        shorebirdEnv.getShorebirdYaml()?.appId;
    if (appId == null) {
      logger.err(
        '''
Could not find an app id.
You must either specify an app id via the "--$_appIdOption" flag or run this command from within a directory with a valid "shorebird.yaml" file.''',
      );
      return ExitCode.usage.code;
    }

    final List<Collaborator> collaborators;
    try {
      collaborators = await codePushClientWrapper.codePushClient
          .getCollaborators(appId: appId);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info(
      '''
📱 App ID: ${lightCyan.wrap(appId)}
🤝 Collaborators''',
    );

    if (collaborators.isEmpty) {
      logger.info('(empty)');
      return ExitCode.success.code;
    }

    logger.info(collaborators.prettyPrint());

    return ExitCode.success.code;
  }
}

extension on List<Collaborator> {
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
              Cell('Email'),
              Cell('Role'),
            ],
          ),
        ],
      ),
      body: TableSection(
        rows: [
          for (final collaborator in this)
            Row(
              cells: [
                Cell(collaborator.email),
                Cell(collaborator.role.name),
              ],
            ),
        ],
      ),
    ).render();
  }
}
