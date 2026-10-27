import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/commands/service_accounts/service_account_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template service_accounts_create_command}
/// `shorebird service-accounts create <name>`
/// Create a service account in an organization.
/// {@endtemplate}
class ServiceAccountsCreateCommand extends ShorebirdCommand
    with OrganizationScopedCommand {
  /// {@macro service_accounts_create_command}
  ServiceAccountsCreateCommand() {
    argParser.addOption(
      'role',
      help: '$serviceAccountRoleHelp Defaults to developer.',
      allowed: serviceAccountRoleValues,
    );
    addOrganizationScopeOption();
  }

  @override
  String get name => 'create';

  @override
  String get invocation => 'shorebird service-accounts create <name>';

  @override
  String get description =>
      'Creates a service account in an organization.\n\n'
      'Example output:\n'
      '  Created service account "release-bot" (id: 383) with role '
      'developer.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird service-accounts create release-bot --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length != 1) {
      return reportError(
        message:
            'Name the service account once: '
            'shorebird service-accounts create release-bot.',
      );
    }
    final accountName = rest.single;
    if (accountName.trim().isEmpty) {
      return reportError(message: 'Service account name must not be blank.');
    }
    final roleArg = results['role'] as String?;
    final role = roleArg == null ? null : ServiceAccountRole.fromJson(roleArg);

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final ServiceAccount account;
    final createError = await guardApiCall(
      () async => account = await codePushClientWrapper.createServiceAccount(
        organizationId: organization.id,
        name: accountName,
        role: role,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to create service account "$accountName".',
    );
    if (createError != null) return createError;

    if (isJsonMode) {
      emitJsonSuccess(serviceAccountJson(account));
      return ExitCode.success.code;
    }

    logger
      ..success(
        'Created service account "${account.name}" (id: ${account.id}) with '
        'role ${account.role.value}.',
      )
      ..info(
        'Give it a key in the console: '
        '${serviceAccountConsoleUri(account)}',
      );
    return ExitCode.success.code;
  }
}

/// The console page for [account], where its keys are made.
Uri serviceAccountConsoleUri(ServiceAccount account) => ShorebirdWebConsole.uri(
  'orgs/${account.organizationId}/settings/service-accounts/${account.id}',
);
