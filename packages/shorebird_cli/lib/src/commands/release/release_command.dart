import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template release_command}
/// `shorebird release`
/// Create new app releases.
/// {@endtemplate}
class ReleaseCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseCommand({required super.logger}) {
    addSubcommand(ReleaseAndroidCommand(logger: logger));
    addSubcommand(ReleaseIosCommand(logger: logger));
  }

  @override
  String get description => 'Manage your Shorebird app releases.';

  @override
  String get name => 'release';
}
