import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_account_trust_command}
/// `shorebird service-accounts trust`
/// Commands for the GitHub Actions workflows a service account trusts.
/// {@endtemplate}
class ServiceAccountTrustCommand extends ShorebirdCommand {
  /// {@macro service_account_trust_command}
  ServiceAccountTrustCommand() {
    addSubcommand(ServiceAccountTrustAddCommand());
    addSubcommand(ServiceAccountTrustListCommand());
    addSubcommand(ServiceAccountTrustRemoveCommand());
  }

  @override
  String get name => 'trust';

  @override
  List<String> get aliases => const ['trust-rules', 'oidc'];

  @override
  String get description =>
      'List, add and remove the GitHub Actions workflows that may sign in as '
      'a service account with their own OIDC token, so CI stores no key.';
}
