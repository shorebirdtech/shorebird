import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template releases_command}
/// Commands for managing Shorebird releases.
/// {@endtemplate}
class ReleasesCommand extends ShorebirdCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(GetApksCommand());
    addSubcommand(ReleasesDeleteCommand());
    addSubcommand(ReleasesInfoCommand());
    addSubcommand(ReleasesListCommand());
  }

  @override
  String get name => 'releases';

  @override
  String get description =>
      'Manage Shorebird releases.\n\n'
      'A release is a build you shipped to a store, and it is what patches '
      'attach to. One release version can carry several platforms.\n\n'
      'Examples:\n'
      '  shorebird releases list\n'
      '  shorebird releases info --release-version 1.0.0+1\n'
      '  shorebird releases get-apks --release-version 1.0.0+1';
}
