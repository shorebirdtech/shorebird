import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

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
      '  created: 2026-01-15\n\n'
      '${ShorebirdCommand.jsonHint('shorebird orgs get --org-id 42 --json')}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganizationFromArguments(
      example: 'shorebird orgs get <org-id>',
    );
    if (errorCode != null) return errorCode;

    final org = membership!.organization;
    if (isJsonMode) {
      emitJsonSuccess({
        'id': org.id,
        'name': org.name,
        'type': org.organizationType.name,
        'role': membership.role.name,
        'created_at': org.createdAt.toUtc().toIso8601String(),
        'updated_at': org.updatedAt.toUtc().toIso8601String(),
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
    return ExitCode.success.code;
  }
}
