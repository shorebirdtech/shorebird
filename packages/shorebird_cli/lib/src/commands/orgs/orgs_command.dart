import 'package:shorebird_cli/src/commands/members/members.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template orgs_command}
/// `shorebird orgs`
/// Commands for the organizations you belong to.
/// {@endtemplate}
class OrgsCommand extends ShorebirdCommand {
  /// {@macro orgs_command}
  OrgsCommand() {
    addSubcommand(OrgsCreateCommand());
    addSubcommand(OrgsGetCommand());
    addSubcommand(OrgsListCommand());
    addSubcommand(OrgsMembersCommand());
    addSubcommand(OrgsServiceAccountsCommand());
    addSubcommand(OrgsUpdateCommand());
  }

  @override
  String get name => 'orgs';

  // Agents guess the long form, and "teams" for the same group of apps and
  // people.
  @override
  List<String> get aliases => const ['organizations', 'org', 'teams'];

  @override
  String get description =>
      'List, create, inspect and rename your organizations. With no '
      'subcommand, lists them (the same as `shorebird orgs list`).';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template account_orgs_command}
/// `shorebird account orgs`
/// The command `shorebird orgs list` replaced, kept hidden so existing
/// scripts keep working.
/// {@endtemplate}
class AccountOrgsCommand extends OrgsListCommand {
  /// {@macro account_orgs_command}
  AccountOrgsCommand();

  @override
  String get name => 'orgs';

  @override
  bool get hidden => true;

  @override
  Future<int> run() {
    if (!isJsonMode) {
      logger.info('`shorebird account orgs` is now `shorebird orgs list`.');
    }
    return super.run();
  }
}
