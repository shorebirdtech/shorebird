import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template channels_command}
/// `shorebird channels`
/// Manage the channels for your Shorebird app.
/// {@endtemplate}
class ChannelsCommand extends ShorebirdCommand {
  /// {@macro channels_command}
  ChannelsCommand({required super.logger}) {
    addSubcommand(CreateChannelsCommand(logger: logger));
    addSubcommand(DeleteChannelsCommand(logger: logger));
    addSubcommand(ListChannelsCommand(logger: logger));
  }

  @override
  String get description => 'Manage the channels for your Shorebird app.';

  @override
  String get name => 'channels';
}
