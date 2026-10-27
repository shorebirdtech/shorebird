import 'package:shorebird_cli/src/commands/apps/apps.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template apps_command}
/// Commands for managing Shorebird apps.
/// {@endtemplate}
class AppsCommand extends ShorebirdCommand {
  /// {@macro apps_command}
  AppsCommand() {
    addSubcommand(AppsArchiveCommand());
    addSubcommand(AppsDeleteCommand());
    addSubcommand(AppsListCommand());
    addSubcommand(AppsRenameCommand());
    addSubcommand(AppsTransferCommand());
    addSubcommand(AppsUnarchiveCommand());
  }

  @override
  String get name => 'apps';

  @override
  String get description =>
      'Manage Shorebird apps.\n\n'
      'An app is the Shorebird-side record that releases and patches belong '
      'to. Its ID is the app_id in shorebird.yaml, and every subcommand here '
      'takes --app-id to work outside a Shorebird project.\n\n'
      'Examples:\n'
      '  shorebird apps list\n'
      '  shorebird apps rename --app-id <id> --name "Acme Consumer"\n'
      '  shorebird apps delete --app-id <id> --confirm-name "<name>"';
}
