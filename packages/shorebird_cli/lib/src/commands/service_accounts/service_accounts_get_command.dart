import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_accounts_get_command}
/// `shorebird service-accounts get <name or id>`
/// Show a service account and its keys.
/// {@endtemplate}
class ServiceAccountsGetCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_accounts_get_command}
  ServiceAccountsGetCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'get';

  @override
  List<String> get aliases => const ['describe'];

  @override
  String get invocation => 'shorebird service-accounts get <name or id>';

  @override
  String get commandLine => 'shorebird service-accounts get';

  @override
  String get description =>
      'Shows a service account and its keys.\n\n'
      'Example output:\n'
      '  release-bot[bot]\n'
      '  id: 383\n'
      '  role: developer\n'
      '  created: 2026-10-01 by admin@acme.com\n'
      '  last signed in: 2026-10-20\n'
      '  keys:\n'
      '    12  ci  created 2026-10-01  expires 2027-10-01  '
      'last used 2026-10-20\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts get release-bot --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
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

    if (isJsonMode) {
      emitJsonSuccess({
        ...serviceAccountJson(account),
        'keys': keys.map(serviceAccountKeyJson).toList(),
      });
      return ExitCode.success.code;
    }

    final createdBy = account.createdByEmail == null
        ? ''
        : ' by ${account.createdByEmail}';
    logger
      ..info(lightCyan.wrap(account.label))
      ..info('id: ${account.id}')
      ..info('role: ${account.role.value}')
      ..info('created: ${formatDate(account.createdAt)}$createdBy')
      ..info('last signed in: ${formatDate(account.lastAuthAt)}');
    if (keys.isEmpty) {
      logger.info('keys: none');
    } else {
      logger.info('keys:');
      for (final key in keys) {
        logger.info('  ${serviceAccountKeyLine(key)}');
      }
    }
    return ExitCode.success.code;
  }
}
