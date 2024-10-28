import 'package:shorebird_cli/src/commands/releases/releases.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template patchesreleases_command}
/// Commands for managing Shorebird releases.
/// {@endtemplate}
class ReleasesCommand extends ShorebirdCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(GetApkCommand());
  }

  @override
  String get name => 'releases';

  @override
  String get description => 'Manage Shorebird releases';
}
