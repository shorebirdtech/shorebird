import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template orgs_create_command}
/// `shorebird orgs create <name>`
/// Create an organization owned by the current user.
/// {@endtemplate}
class OrgsCreateCommand extends ShorebirdCommand {
  /// {@macro orgs_create_command}
  OrgsCreateCommand() {
    argParser.addOption(
      'name',
      help:
          'The name of the new organization (e.g. "Acme Corp"). May be '
          'passed as the only argument instead.',
    );
  }

  @override
  String get name => 'create';

  @override
  String get invocation => 'shorebird orgs create <name>';

  @override
  String get description =>
      'Creates an organization, with you as its owner.\n\n'
      'Example output:\n'
      '  Created organization "Acme Corp" (id: 42).\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs create "Acme Corp" --json',
      )}';

  @override
  Future<int> run() async {
    final nameOption = results['name'] as String?;
    final rest = results.rest;
    if (rest.length > 1 || (nameOption != null && rest.isNotEmpty)) {
      return reportError(
        message:
            'Pass the organization name once, quoted if it has spaces: '
            'shorebird orgs create "Acme Corp".',
      );
    }
    final organizationName = nameOption ?? rest.firstOrNull;
    if (organizationName == null) {
      return reportError(
        message: 'Name the organization: shorebird orgs create "Acme Corp".',
      );
    }
    if (organizationName.trim().isEmpty) {
      return reportError(message: 'Organization name must not be blank.');
    }

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final Organization organization;
    final createError = await guardApiCall(
      () async => organization = await codePushClientWrapper.createOrganization(
        name: organizationName,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to create organization "$organizationName".',
    );
    if (createError != null) return createError;

    if (isJsonMode) {
      emitJsonSuccess({
        'id': organization.id,
        'name': organization.name,
        'type': organization.organizationType.name,
        'role': Role.owner.name,
      });
      return ExitCode.success.code;
    }

    logger.success(
      'Created organization "${organization.name}" '
      '(id: ${organization.id}).',
    );
    return ExitCode.success.code;
  }
}
