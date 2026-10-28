import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template orgs_list_command}
/// `shorebird orgs list`
/// List the organizations the current user can access.
/// {@endtemplate}
class OrgsListCommand extends ShorebirdCommand with EnterpriseScopedCommand {
  /// {@macro orgs_list_command}
  OrgsListCommand() {
    addEnterpriseScopeFlag(
      help:
          'List every organization in your enterprise, including ones you '
          "aren't in. Needs an owner or admin of the enterprise.",
    );
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the organizations you can access.\n\n'
      'Example output (space-separated: id  name  type  role):\n'
      '  1  Acme Corp  team  admin\n'
      '  2  user@example.com  personal  owner\n\n'
      'Type is "personal" or "team".\n'
      'Role is "owner", "admin", "appManager", "developer", "viewer", or '
      '"none".\n'
      'A "none" role means you only collaborate on apps in that organization.'
      '\n\n'
      'With --enterprise, lists every organization in the enterprise '
      '(space-separated: id  name  members  apps):\n'
      '  42  Mobile  12 members  3 apps\n\n'
      '${ShorebirdCommand.jsonHint('shorebird orgs list --json')}';

  @override
  Future<int> run() async {
    if (enterpriseScope) return _listEnterpriseOrganizations();
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final List<OrganizationMembership> memberships;
    final fetchError = await guardApiCall(
      () async => memberships = await codePushClientWrapper
          .getOrganizationMemberships(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch organizations.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'organizations': [
          for (final m in memberships)
            {
              'id': m.organization.id,
              'name': m.organization.name,
              'type': m.organization.organizationType.name,
              'role': m.role.name,
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (memberships.isEmpty) {
      logger.info('No organizations found.');
      return ExitCode.success.code;
    }

    for (final membership in memberships) {
      final org = membership.organization;
      logger.info(
        '${org.id}  ${lightCyan.wrap(org.name)}  '
        '${org.organizationType.name}  ${membership.role.name}',
      );
    }

    return ExitCode.success.code;
  }

  Future<int> _listEnterpriseOrganizations() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final List<EnterpriseTeam> organizations;
    final fetchError = await guardApiCall(
      () async => organizations = await codePushClientWrapper
          .getEnterpriseOrganizations(enterpriseId: enterprise.id),
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the organizations of enterprise ${enterprise.id}.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'organizations': [
          for (final org in organizations)
            {
              'id': org.id,
              'name': org.name,
              'member_count': org.memberCount,
              'app_count': org.appCount,
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (organizations.isEmpty) {
      logger.info('"${enterprise.name}" has no organizations.');
      return ExitCode.success.code;
    }
    for (final org in organizations) {
      logger.info(
        '${org.id}  ${lightCyan.wrap(org.name)}  '
        '${formatCount(org.memberCount, 'member')}  '
        '${formatCount(org.appCount, 'app')}',
      );
    }
    return ExitCode.success.code;
  }
}
