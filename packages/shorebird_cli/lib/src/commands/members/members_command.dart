import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template members_command}
/// `shorebird orgs members`
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
  List<String> get aliases => const ['users', 'collaborators'];

  @override
  String get description =>
      "List, invite and remove an organization's members, and change their "
      'roles. With no subcommand, lists them (the same as '
      '`shorebird orgs members list`).';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template top_level_members_command}
/// `shorebird members`
/// `shorebird orgs members` at the top level, hidden, because agents guess
/// it there.
/// {@endtemplate}
class TopLevelMembersCommand extends MembersCommand {
  /// {@macro top_level_members_command}
  TopLevelMembersCommand();

  @override
  List<String> get aliases => const ['collaborators'];

  @override
  bool get hidden => true;
}
