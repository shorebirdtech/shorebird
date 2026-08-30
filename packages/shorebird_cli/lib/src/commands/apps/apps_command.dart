import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template apps_command}
/// Commands for managing Shorebird apps.
/// {@endtemplate}
class AppsCommand extends ShorebirdCommand {
  /// {@macro apps_command}
  AppsCommand() {
    addSubcommand(AppsDeleteCommand());
    addSubcommand(AppsRenameCommand());
    addSubcommand(AppsTransferCommand());
  }

  @override
  String get name => 'apps';

  @override
  String get description => 'Manage Shorebird apps.';
}
