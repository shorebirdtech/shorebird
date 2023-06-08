import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/releases/releases.dart';

/// {@template releases_command}
///
/// `shorebird releases`
/// Manage your Shorebird releases.
/// {@endtemplate}
class ReleasesCommand extends ShorebirdCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(DeleteReleasesCommand());
    addSubcommand(ListReleasesCommand());
  }

  @override
  String get name => 'releases';

  @override
  String get description => 'Manage your releases.';
}
