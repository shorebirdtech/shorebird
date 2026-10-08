import 'package:shorebird_cli/src/commands/account/apps_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template apps_list_command}
/// `shorebird apps list`
/// List the apps the current user has access to.
/// {@endtemplate}
///
/// The same listing as `shorebird account apps`, reachable from the group that
/// holds the rest of the app verbs. `apps delete` needs a display name to echo
/// back, and requiring a different top-level group to find it makes the delete
/// undiscoverable.
class AppsListCommand extends AccountAppsCommand {
  /// {@macro apps_list_command}
  AppsListCommand();

  @override
  String get name => 'list';

  @override
  String get description =>
      'Lists the apps you have access to.\n\n'
      'Example output (space-separated: app_id  display_name  '
      'latest_release_version  latest_patch_number):\n'
      '  01H...  Acme Mobile  1.2.3  4\n'
      '  01J...  Acme Internal  -  -\n\n'
      '"-" indicates no release or patch has been published yet.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird apps list --json')}';
}
