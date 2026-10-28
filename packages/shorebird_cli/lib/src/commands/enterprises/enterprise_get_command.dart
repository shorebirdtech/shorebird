import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template enterprise_get_command}
/// `shorebird enterprise get`
/// Show your enterprise's name, domains and your role in it.
/// {@endtemplate}
class EnterpriseGetCommand extends ShorebirdCommand
    with EnterpriseScopedCommand {
  /// {@macro enterprise_get_command}
  EnterpriseGetCommand();

  @override
  String get name => 'get';

  @override
  String get description =>
      "Shows your enterprise's name, its domains and your role in it. Needs "
      'an owner or admin of the enterprise.\n\n'
      'Example output:\n'
      '  Acme (id: 7)\n'
      '  Domains: acme.com, acme.dev\n'
      '  Your role: admin\n\n'
      'Role is "owner", "admin", "billingManager" or "member".\n\n'
      '${ShorebirdCommand.jsonHint('shorebird enterprise get --json')}';

  @override
  Future<int> run() async {
    if (results.rest.isNotEmpty) {
      return reportError(
        message:
            '`shorebird enterprise get` takes no arguments: an account is in '
            'at most one enterprise.',
      );
    }
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final role = membership!.role;

    late final Enterprise enterprise;
    final fetchError = await guardApiCall(
      () async => enterprise = await codePushClientWrapper.getEnterprise(
        enterpriseId: membership.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch enterprise ${membership.id}.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'id': enterprise.id,
        'name': enterprise.name,
        'role': role.value,
        'domains': enterprise.domains,
      });
      return ExitCode.success.code;
    }
    final domains = enterprise.domains;
    logger
      ..info('${lightCyan.wrap(enterprise.name)} (id: ${enterprise.id})')
      ..info('Domains: ${domains.isEmpty ? 'none' : domains.join(', ')}')
      ..info('Your role: ${role.value}');
    return ExitCode.success.code;
  }
}
