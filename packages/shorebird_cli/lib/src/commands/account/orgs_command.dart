import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template orgs_command}
/// `shorebird account orgs`
/// List the organizations the current user belongs to.
/// {@endtemplate}
class OrgsCommand extends ShorebirdCommand {
  /// {@macro orgs_command}
  OrgsCommand();

  @override
  String get name => 'orgs';

  @override
  String get description =>
      'List the organizations you belong to.\n\n'
      'Example output (space-separated: id  name  type  role):\n'
      '  1  Acme Corp  team  admin\n'
      '  2  user@example.com  personal  owner\n\n'
      'Type is "personal" or "team". Role is "owner", "admin", or '
      '"developer".\n\n'
      '${ShorebirdCommand.jsonHint('shorebird account orgs --json')}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final List<OrganizationMembership> memberships;
    try {
      memberships = await codePushClientWrapper.getOrganizationMemberships();
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch organizations.',
        );
        return e.exitCode;
      }
      rethrow;
    }

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
