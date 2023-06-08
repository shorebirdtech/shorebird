import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template apps_command}
///
/// `shorebird apps`
/// Manage your Shorebird apps.
/// {@endtemplate}
class AppsCommand extends ShorebirdCommand {
  /// {@macro apps_command}
  AppsCommand() {
    addSubcommand(CreateAppCommand());
    addSubcommand(DeleteAppCommand());
    addSubcommand(ListAppsCommand());
  }

  @override
  String get description => 'Manage your Shorebird apps.';

  @override
  String get name => 'apps';
}
