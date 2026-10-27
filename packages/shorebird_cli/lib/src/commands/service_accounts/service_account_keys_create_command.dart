import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts_create_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_account_keys_create_command}
/// `shorebird service-accounts keys create <name or id>`
/// Open the console page where a service account's keys are made.
/// {@endtemplate}
class ServiceAccountKeysCreateCommand extends ShorebirdCommand
    with
        FinishInConsole,
        OrganizationScopedCommand,
        ServiceAccountScopedCommand {
  /// {@macro service_account_keys_create_command}
  ServiceAccountKeysCreateCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'create';

  @override
  String get invocation =>
      'shorebird service-accounts keys create '
      '<service account name or id>';

  @override
  String get commandLine => 'shorebird service-accounts keys create';

  @override
  String get description =>
      "Opens the console page where a service account's keys are made; the "
      "key's secret is shown once, there. The CLI does not make keys, so that "
      'a person, not a script or agent, mints each long-lived credential. '
      'Without a terminal (or with --json) it fails with the page URL. To let '
      'GitHub Actions sign in without a key, add a trust rule instead.';

  @override
  Future<int> run() async {
    final (:resolved, :errorCode) = await resolveServiceAccount();
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    return finishInConsole(
      action: 'make keys for service account "${account.name}"',
      url: serviceAccountConsoleUri(account),
    );
  }
}
