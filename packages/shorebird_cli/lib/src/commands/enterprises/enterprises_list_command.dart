import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template enterprises_list_command}
/// `shorebird enterprises list`
/// List the enterprises the current user belongs to.
/// {@endtemplate}
class EnterprisesListCommand extends ShorebirdCommand {
  /// {@macro enterprises_list_command}
  EnterprisesListCommand();

  @override
  String get name => 'list';

  @override
  String get description =>
      'Lists the enterprises you belong to.\n\n'
      'Example output (space-separated: id  name  role):\n'
      '  7  Acme  admin\n\n'
      'Role is "owner", "admin", "billingManager" or "member".\n\n'
      '${ShorebirdCommand.jsonHint('shorebird enterprises list --json')}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final List<EnterpriseMembership> enterprises;
    final fetchError = await guardApiCall(
      () async => enterprises = await codePushClientWrapper.getEnterprises(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch enterprises.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprises': [
          for (final e in enterprises)
            {'id': e.id, 'name': e.name, 'role': e.role.value},
        ],
      });
      return ExitCode.success.code;
    }

    if (enterprises.isEmpty) {
      logger.info('You are not a member of any enterprise.');
      return ExitCode.success.code;
    }
    for (final e in enterprises) {
      logger.info('${e.id}  ${lightCyan.wrap(e.name)}  ${e.role.value}');
    }
    return ExitCode.success.code;
  }
}
