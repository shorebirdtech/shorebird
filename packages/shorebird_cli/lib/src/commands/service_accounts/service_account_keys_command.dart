import 'package:shorebird_cli/src/commands/service_accounts/service_accounts.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template service_account_keys_command}
/// `shorebird service-accounts keys`
/// Commands for a service account's API keys.
/// {@endtemplate}
class ServiceAccountKeysCommand extends ShorebirdCommand {
  /// {@macro service_account_keys_command}
  ServiceAccountKeysCommand() {
    addSubcommand(ServiceAccountKeysCreateCommand());
    addSubcommand(ServiceAccountKeysListCommand());
    addSubcommand(ServiceAccountKeysRevokeCommand());
  }

  @override
  String get name => 'keys';

  @override
  List<String> get aliases => const ['credentials'];

  @override
  String get description =>
      "List and revoke a service account's API keys. Keys are made in the "
      'console.';
}
