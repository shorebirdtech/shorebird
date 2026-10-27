import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template orgs_update_command}
/// `shorebird orgs update`
/// Rename an organization.
/// {@endtemplate}
class OrgsUpdateCommand extends ShorebirdCommand
    with OrganizationScopedCommand {
  /// {@macro orgs_update_command}
  OrgsUpdateCommand() {
    argParser.addOption(
      'name',
      help: 'The new name of the organization (e.g. "Acme Corp").',
      mandatory: true,
    );
    addOrganizationScopeOption();
  }

  @override
  String get name => 'update';

  @override
  List<String> get aliases => const ['rename'];

  @override
  String get description =>
      'Renames an organization.\n\n'
      'Example output:\n'
      '  Renamed "Acme" to "Acme Corp".\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird orgs update --org-id 42 --name "Acme Corp" --json',
      )}';

  @override
  Future<int> run() async {
    final newName = results['name'] as String;
    if (newName.trim().isEmpty) {
      return reportError(message: 'Organization name must not be blank.');
    }

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    if (organization.name == newName) {
      return reportError(
        message: 'Organization ${organization.id} is already named "$newName".',
      );
    }

    final updateError = await guardApiCall(
      () => codePushClientWrapper.updateOrganization(
        organizationId: organization.id,
        name: newName,
      ),
      code: JsonErrorCode.softwareError,
      message: 'Failed to rename organization ${organization.id}.',
    );
    if (updateError != null) return updateError;

    if (isJsonMode) {
      emitJsonSuccess({
        'id': organization.id,
        'from_name': organization.name,
        'to_name': newName,
      });
      return ExitCode.success.code;
    }

    logger.success('Renamed "${organization.name}" to "$newName".');
    return ExitCode.success.code;
  }
}
