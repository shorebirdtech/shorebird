import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_accounts_command}
/// `shorebird service-accounts`
/// Commands for an organization's service accounts.
/// {@endtemplate}
class ServiceAccountsCommand extends ShorebirdCommand {
  /// {@macro service_accounts_command}
  ServiceAccountsCommand() {
    addSubcommand(ServiceAccountsCreateCommand());
    addSubcommand(ServiceAccountsDeleteCommand());
    addSubcommand(ServiceAccountsGetCommand());
    addSubcommand(ServiceAccountKeysCommand());
    addSubcommand(ServiceAccountsListCommand());
    addSubcommand(ServiceAccountsSetRoleCommand());
  }

  @override
  String get name => 'service-accounts';

  @override
  List<String> get aliases => const ['service-account'];

  @override
  String get description =>
      "Manage an organization's service accounts: credentials for CI that "
      'belong to the organization rather than to a person. With no '
      'subcommand, lists them (the same as `shorebird service-accounts '
      'list`).';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template orgs_service_accounts_command}
/// `shorebird orgs service-accounts`
/// The same commands as `shorebird service-accounts`, hidden under `orgs` for
/// those who look for them there. Like `gh secret`, org-scoped nouns are
/// top-level and take `--org-id`.
/// {@endtemplate}
class OrgsServiceAccountsCommand extends ServiceAccountsCommand {
  /// {@macro orgs_service_accounts_command}
  OrgsServiceAccountsCommand();

  @override
  bool get hidden => true;
}
