import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template orgs_list_command}
/// `shorebird orgs list`
/// List the organizations the current user can access.
/// {@endtemplate}
class OrgsListCommand extends ShorebirdCommand {
  /// {@macro orgs_list_command}
  OrgsListCommand();

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
      '${ShorebirdCommand.jsonHint('shorebird orgs list --json')}';

  @override
  Future<int> run() async {
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
}
