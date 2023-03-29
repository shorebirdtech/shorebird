import 'dart:async';

import 'package:barbecue/barbecue.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template list_channels_command}
/// `shorebird channels list`
/// List all channels for a Shorebird app.
/// {@endtemplate}
class ListChannelsCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro list_channels_command}
  ListChannelsCommand({
    required super.logger,
    super.buildCodePushClient,
    super.auth,
  }) {
    argParser.addOption(
      'app-id',
      help: 'The app id to list channels for.',
    );
  }

  @override
  String get description => 'List all channels for a Shorebird app.';

  @override
  String get name => 'list';

  @override
  List<String> get aliases => ['ls'];

  @override
  Future<int>? run() async {
    final session = auth.currentSession;
    if (session == null) {
      logger.err('You must be logged in to view channels.');
      return ExitCode.noUser.code;
    }

    final client = buildCodePushClient(
      apiKey: session.apiKey,
      hostedUri: hostedUri,
    );

    final appId = results['app-id'] as String? ?? getShorebirdYaml()?.appId;
    if (appId == null) {
      logger.err(
        '''
Could not find an app-id.

You must either specify an app id via the --app-id flag or run this command from within a directory with a valid "shorebird.yaml" file.''',
      );
      return ExitCode.usage.code;
    }

    final List<Channel> channels;
    try {
      channels = await client.getChannels(appId: appId);
    } catch (error) {
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.info(
      '''
📱 App ID: ${lightCyan.wrap(appId)}
📺 Channels''',
    );

    if (channels.isEmpty) {
      logger.info('(empty)');
      return ExitCode.success.code;
    }

    logger.info(channels.prettyPrint());

    return ExitCode.success.code;
  }
}

extension on List<Channel> {
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
          Row(cells: [Cell('ID'), Cell('Name')])
        ],
      ),
      body: TableSection(
        rows: [
          for (final channel in this)
            Row(
              cells: [
                Cell(channel.id.toString()),
                Cell(channel.name),
              ],
            ),
        ],
      ),
    ).render();
  }
}
