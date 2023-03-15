import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template apps_command}
///
/// `shorebird apps`
/// Manage your Shorebird apps.
/// {@endtemplate}
class AppsCommand extends ShorebirdCommand {
  /// {@macro apps_command}
  AppsCommand({required super.logger}) {
    addSubcommand(CreateAppCommand(logger: logger));
    addSubcommand(DeleteAppCommand(logger: logger));
    addSubcommand(ListAppsCommand(logger: logger));
  }

  @override
  String get description => 'Manage your Shorebird apps.';

  @override
  String get name => 'apps';
}
