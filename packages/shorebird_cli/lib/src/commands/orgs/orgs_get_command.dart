import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template orgs_get_command}
/// `shorebird orgs get`
/// Show one organization and your role in it.
/// {@endtemplate}
class OrgsGetCommand extends ShorebirdCommand with OrganizationScopedCommand {
  /// {@macro orgs_get_command}
  OrgsGetCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'get';

  @override
  String get invocation => 'shorebird orgs get [<org-id>]';

  @override
  String get description =>
      'Shows an organization and your role in it.\n\n'
      'Example output:\n'
      '  Acme Corp\n'
      '  id: 42\n'
      '  type: team\n'
      '  your role: admin\n'
      '  created: 2026-01-15\n'
      '  patch installs: 12,345 of 50,000 included\n\n'
      'Patch installs are left out for roles that may not see usage (auditor); '
      '`shorebird orgs usage` shows the details.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird orgs get 42 --json')}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganizationFromArguments(
      example: 'shorebird orgs get <org-id>',
    );
    if (errorCode != null) return errorCode;

    final org = membership!.organization;

    GetUsageResponse? usage;
    final usageError = await guardApiCall(
      () async => usage = await codePushClientWrapper.maybeGetOrganizationUsage(
        organizationId: org.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch usage for organization ${org.id}.',
    );
    if (usageError != null) return usageError;
    final position = usage?.position;

    if (isJsonMode) {
      emitJsonSuccess({
        'id': org.id,
        'name': org.name,
        'type': org.organizationType.name,
        'role': membership.role.name,
        'created_at': org.createdAt.toUtc().toIso8601String(),
        'updated_at': org.updatedAt.toUtc().toIso8601String(),
        'usage': position?.toJson(),
      });
      return ExitCode.success.code;
    }

    logger
      ..info(lightCyan.wrap(org.name))
      ..info('id: ${org.id}')
      ..info('type: ${org.organizationType.name}')
      ..info('your role: ${membership.role.name}')
      ..info(
        'created: ${org.createdAt.toUtc().toIso8601String().substring(0, 10)}',
      );
    if (position != null) {
      final number = NumberFormat.decimalPattern('en_US');
      logger.info(
        'patch installs: ${number.format(position.installs)} of '
        '${number.format(position.includedInstalls)} included',
      );
    }
    return ExitCode.success.code;
  }
}
