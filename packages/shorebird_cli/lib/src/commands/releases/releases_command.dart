import 'package:shorebird_cli/src/commands/releases/list_releases_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template releases_command}
/// Commands for Shorebird releases.
/// {@endtemplate}
class ReleasesCommand extends ShorebirdCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(ListReleasesCommand());
  }

  @override
  String get description => 'Commands for Shorebird releases.';

  @override
  String get name => 'releases';
}
