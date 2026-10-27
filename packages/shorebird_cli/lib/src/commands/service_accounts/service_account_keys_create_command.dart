import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_accounts_create_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_account_keys_create_command}
/// `shorebird service-accounts keys create <name or id>`
/// Point at the console page where a service account's keys are made.
/// {@endtemplate}
class ServiceAccountKeysCreateCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_keys_create_command}
  ServiceAccountKeysCreateCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'create';

  @override
  String get invocation =>
      'shorebird service-accounts keys create <service account name or id>';

  @override
  String get commandLine => 'shorebird service-accounts keys create';

  @override
  String get description =>
      "Prints the console page where a service account's keys are made. "
      'The CLI does not make keys, so that a person, not a script or agent, '
      'mints each long-lived credential. To let GitHub Actions sign in '
      'without a key, add a trust rule instead.';

  @override
  Future<int> run() async {
    final (:resolved, :errorCode) = await resolveServiceAccount(
      results.rest.firstOrNull,
    );
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    return reportError(
      message:
          'Make keys for "${account.name}" in the console; the CLI does not '
          'make them.',
      hint: 'Open ${serviceAccountConsoleUri(account)}',
      exitCode: 1,
    );
  }
}
