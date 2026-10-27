import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_account_keys_list_command}
/// `shorebird service-accounts keys list <name or id>`
/// List a service account's unrevoked keys.
/// {@endtemplate}
class ServiceAccountKeysListCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_keys_list_command}
  ServiceAccountKeysListCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'list';

  @override
  String get invocation =>
      'shorebird service-accounts keys list <service account name or id>';

  @override
  String get commandLine => 'shorebird service-accounts keys list';

  @override
  String get description =>
      "Lists a service account's API keys that have not been revoked, "
      'newest first. A key past its expiry is listed until revoked.\n\n'
      'Example output:\n'
      '  12  ci  created 2026-10-01  expires 2027-10-01  '
      'last used 2026-10-20\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts keys list release-bot --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:resolved, :errorCode) = await resolveServiceAccount(
      results.rest.firstOrNull,
    );
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    late final List<ServiceAccountKey> keys;
    final fetchError = await guardApiCall(
      () async => keys = await codePushClientWrapper.getServiceAccountKeys(
        organizationId: account.organizationId,
        serviceAccountId: account.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the keys of "${account.name}".',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'service_account_id': account.id,
        'keys': keys.map(serviceAccountKeyJson).toList(),
      });
      return ExitCode.success.code;
    }

    if (keys.isEmpty) {
      logger.info('"${account.name}" has no keys.');
      return ExitCode.success.code;
    }
    for (final key in keys) {
      logger.info(serviceAccountKeyLine(key));
    }
    return ExitCode.success.code;
  }
}
