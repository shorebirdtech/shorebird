import 'package:shorebird_cli/src/commands/apps/apps_list_command.dart';
import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs_list_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts_list_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

// The nouns under `shorebird enterprise`. Each runs the same command as the
// noun at the top level, built with `enterpriseRoute: true`, so it acts on
// every organization in the user's enterprise; there is one implementation.

/// {@template enterprise_members_command}
/// `shorebird enterprise members`
/// The people in your enterprise's directory.
/// {@endtemplate}
class EnterpriseMembersCommand extends ShorebirdCommand {
  /// {@macro enterprise_members_command}
  EnterpriseMembersCommand() {
    addSubcommand(MembersListCommand(enterpriseRoute: true));
    addSubcommand(MembersRemoveCommand(enterpriseRoute: true));
    addSubcommand(MembersSetRoleCommand(enterpriseRoute: true));
  }

  @override
  String get name => 'members';

  @override
  List<String> get aliases => const ['member', 'people', 'users'];

  @override
  String get description =>
      "List your enterprise's directory, change enterprise roles, and remove "
      'people from the enterprise. With no subcommand, lists them (the same '
      'as `shorebird enterprise members list`).';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template enterprise_guests_command}
/// `shorebird enterprise guests`
/// The people in your enterprise's organizations who aren't in its
/// directory.
/// {@endtemplate}
class EnterpriseGuestsCommand extends ShorebirdCommand {
  /// {@macro enterprise_guests_command}
  EnterpriseGuestsCommand() {
    addSubcommand(MembersListCommand(enterpriseRoute: true, guestsRoute: true));
  }

  @override
  String get name => 'guests';

  @override
  List<String> get aliases => const ['guest'];

  @override
  String get description =>
      "List your enterprise's guests: people in its organizations who "
      "aren't in its directory. With no subcommand, lists them.";

  @override
  String get defaultSubcommand => 'list';
}

/// {@template enterprise_orgs_command}
/// `shorebird enterprise orgs`
/// Every organization in your enterprise.
/// {@endtemplate}
class EnterpriseOrgsCommand extends ShorebirdCommand {
  /// {@macro enterprise_orgs_command}
  EnterpriseOrgsCommand() {
    addSubcommand(OrgsListCommand(enterpriseRoute: true));
  }

  @override
  String get name => 'orgs';

  @override
  List<String> get aliases => const ['organizations', 'org', 'teams'];

  @override
  String get description =>
      'List every organization in your enterprise, including ones you '
      "aren't in. With no subcommand, lists them.";

  @override
  String get defaultSubcommand => 'list';
}

/// {@template enterprise_apps_command}
/// `shorebird enterprise apps`
/// Every app in your enterprise.
/// {@endtemplate}
class EnterpriseAppsCommand extends ShorebirdCommand {
  /// {@macro enterprise_apps_command}
  EnterpriseAppsCommand() {
    addSubcommand(AppsListCommand(enterpriseRoute: true));
  }

  @override
  String get name => 'apps';

  @override
  List<String> get aliases => const ['app'];

  @override
  String get description =>
      'List every app in every organization of your enterprise. With no '
      'subcommand, lists them.';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template enterprise_service_accounts_command}
/// `shorebird enterprise service-accounts`
/// Every organization's service accounts in your enterprise.
/// {@endtemplate}
class EnterpriseServiceAccountsCommand extends ShorebirdCommand {
  /// {@macro enterprise_service_accounts_command}
  EnterpriseServiceAccountsCommand() {
    addSubcommand(ServiceAccountsListCommand(enterpriseRoute: true));
  }

  @override
  String get name => 'service-accounts';

  @override
  List<String> get aliases => const ['service-account'];

  @override
  String get description =>
      "List every organization's service accounts in your enterprise. With "
      'no subcommand, lists them. They stay owned by their organization: '
      'create, change or delete one with `shorebird service-accounts`.';

  @override
  String get defaultSubcommand => 'list';
}
