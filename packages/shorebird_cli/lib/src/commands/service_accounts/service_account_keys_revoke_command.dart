import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_account_keys_revoke_command}
/// `shorebird orgs service-accounts keys revoke <name or id> <key id>`
/// Revoke one of a service account's keys.
/// {@endtemplate}
class ServiceAccountKeysRevokeCommand extends ShorebirdCommand
    with ConfirmDelete, OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_account_keys_revoke_command}
  ServiceAccountKeysRevokeCommand() {
    addConfirmDeleteOptions(deprecatedConfirmName: false);
    addOrganizationScopeOption();
  }

  @override
  String get name => 'revoke';

  @override
  List<String> get aliases => const ['delete'];

  @override
  String get invocation =>
      'shorebird orgs service-accounts keys revoke '
      '<service account name or id> <key id>';

  @override
  String get commandLine => 'shorebird orgs service-accounts keys revoke';

  @override
  int get maxArguments => 2;

  @override
  String get description =>
      "Revokes one of a service account's API keys. It stops signing in at "
      'once.\n\n'
      'Example output:\n'
      '  Revoked key 12 ("ci") of "release-bot".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts keys revoke release-bot 12 '
        '--org-id 42 --yes --json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    final (:resolved, :errorCode) = await resolveServiceAccount();
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

    final keyIdArg = rest.length > 1 ? rest[1] : null;
    final keyId = keyIdArg == null ? null : int.tryParse(keyIdArg);
    final key = keys.firstWhereOrNull((k) => k.id == keyId);
    if (key == null) {
      final hint = keys.isEmpty
          ? '"${account.name}" has no keys.'
          : 'Keys of "${account.name}": '
                '${keys.map((k) => '${k.id} ("${k.name}")').join(', ')}.';
      return reportError(
        message: keyIdArg == null
            ? 'Name the key to revoke: $commandLine '
                  '${shellQuote(account.name)} <key id>.'
            : '"${account.name}" has no key $keyIdArg.',
        hint: hint,
      );
    }

    final confirmError = confirmDelete(
      name: '${key.id}',
      description: 'key ${key.id} ("${key.name}") of "${account.name}"',
      consequence: 'CI that uses key ${key.id} stops signing in at once.',
    );
    if (confirmError != null) return confirmError;

    final revokeError = await guardApiCall(
      () => codePushClientWrapper.revokeServiceAccountKey(
        organizationId: account.organizationId,
        serviceAccountId: account.id,
        keyId: key.id,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to revoke key ${key.id} of "${account.name}".',
    );
    if (revokeError != null) return revokeError;

    if (isJsonMode) {
      emitJsonSuccess({'service_account_id': account.id, 'key_id': key.id});
      return ExitCode.success.code;
    }

    logger.success(
      'Revoked key ${key.id} ("${key.name}") of "${account.name}".',
    );
    return ExitCode.success.code;
  }
}
