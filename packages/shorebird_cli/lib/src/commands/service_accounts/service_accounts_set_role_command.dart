import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_accounts_set_role_command}
/// `shorebird orgs service-accounts set-role <name or id> --role <role>`
/// Change a service account's role.
/// {@endtemplate}
class ServiceAccountsSetRoleCommand extends ShorebirdCommand
    with OrganizationScopedCommand, ServiceAccountScopedCommand {
  /// {@macro service_accounts_set_role_command}
  ServiceAccountsSetRoleCommand() {
    argParser.addOption(
      'role',
      help: serviceAccountRoleHelp,
      allowed: serviceAccountRoleValues,
      mandatory: true,
    );
    addOrganizationScopeOption();
  }

  @override
  String get name => 'set-role';

  @override
  String get invocation =>
      'shorebird orgs service-accounts set-role <name or id> --role <role>';

  @override
  String get commandLine => 'shorebird orgs service-accounts set-role';

  @override
  String get description =>
      "Changes a service account's role. Its keys and trust rules act with "
      'the new role at once.\n\n'
      'Example output:\n'
      '  Changed the role of "release-bot" from developer to appManager.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs service-accounts set-role release-bot --role viewer '
        '--org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final role = ServiceAccountRole.fromJson(results['role'] as String);
    final (:resolved, :errorCode) = await resolveServiceAccount();
    if (errorCode != null) return errorCode;
    final account = resolved!.account;

    late final ServiceAccount updated;
    final updateError = await guardApiCall(
      () async => updated = await codePushClientWrapper.updateServiceAccount(
        organizationId: account.organizationId,
        serviceAccountId: account.id,
        role: role,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to change the role of "${account.name}".',
    );
    if (updateError != null) return updateError;

    if (isJsonMode) {
      emitJsonSuccess({
        ...serviceAccountJson(updated),
        'from_role': account.role.value,
      });
      return ExitCode.success.code;
    }

    logger.success(
      'Changed the role of "${account.name}" from ${account.role.value} to '
      '${updated.role.value}.',
    );
    return ExitCode.success.code;
  }
}
