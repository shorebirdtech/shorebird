import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template members_command}
/// `shorebird members`
/// Commands for the people in an organization, scoped by `--org-id` the way
/// `gh secret` is scoped by repository.
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
      '`shorebird members list`).\n\n'
      "Pass --enterprise to list, change or remove an enterprise's "
      'members across all its organizations.';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template orgs_members_command}
/// `shorebird orgs members`
/// `shorebird members` under `orgs`, hidden, because agents guess it there.
/// {@endtemplate}
class OrgsMembersCommand extends MembersCommand {
  /// {@macro orgs_members_command}
  OrgsMembersCommand();

  @override
  List<String> get aliases => const ['users', 'collaborators'];

  @override
  bool get hidden => true;
}
