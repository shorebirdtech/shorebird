import 'package:shorebird_cli/src/commands/channels/channels.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template channels_command}
/// Commands for managing the channels (deployment tracks) of an app.
/// {@endtemplate}
class ChannelsCommand extends ShorebirdCommand {
  /// {@macro channels_command}
  ChannelsCommand() {
    addSubcommand(ChannelsCreateCommand());
    addSubcommand(ChannelsDeleteCommand());
    addSubcommand(ChannelsListCommand());
  }

  @override
  String get name => 'channels';

  @override
  String get description => 'Manage the channels an app can publish to.';
}
