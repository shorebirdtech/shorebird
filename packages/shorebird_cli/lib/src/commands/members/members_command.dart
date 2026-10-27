import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template members_command}
/// `shorebird members`
/// Commands for the people in an organization.
/// {@endtemplate}
class MembersCommand extends ShorebirdCommand {
  /// {@macro members_command}
  MembersCommand() {
    addSubcommand(MembersAddCommand());
    addSubcommand(MembersListCommand());
    addSubcommand(MembersRemoveCommand());
    addSubcommand(MembersSetRoleCommand());
  }

  @override
  String get name => 'members';

  // Older Shorebird docs called them collaborators, and agents still guess
  // it.
  @override
  List<String> get aliases => const ['collaborators', 'member'];

  @override
  String get description =>
      "List, invite and remove an organization's members, and change their "
      'roles. With no subcommand, lists them (the same as '
      '`shorebird members list`).';

  @override
  String get defaultSubcommand => 'list';
}
