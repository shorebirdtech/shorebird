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
      "Shows your enterprise's name and your role in it, and to owners and "
      'admins its domains.\n\n'
      'Example output:\n'
      '  Acme (id: 7)\n'
      '  Domains: acme.com, acme.dev\n'
      '  Your role: admin\n\n'
      'Role is "owner", "admin", "billingManager" or "member". Members and '
      'billing managers see no Domains line, and `domains` is null in '
      '--json.\n\n'
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

    // Only owners and admins may read the enterprise itself, which is all
    // the domains add; everyone else gets what the membership says.
    List<String>? domains;
    if (role == EnterpriseRole.owner || role == EnterpriseRole.admin) {
      late final Enterprise enterprise;
      final fetchError = await guardApiCall(
        () async => enterprise = await codePushClientWrapper.getEnterprise(
          enterpriseId: membership.id,
        ),
        code: JsonErrorCode.fetchFailed,
        message: 'Failed to fetch "${membership.name}".',
      );
      if (fetchError != null) return fetchError;
      domains = enterprise.domains;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'id': membership.id,
        'name': membership.name,
        'role': role.value,
        'domains': domains,
      });
      return ExitCode.success.code;
    }
    logger.info('${lightCyan.wrap(membership.name)} (id: ${membership.id})');
    if (domains != null) {
      logger.info('Domains: ${domains.isEmpty ? 'none' : domains.join(', ')}');
    }
    logger.info('Your role: ${role.value}');
    return ExitCode.success.code;
  }
}
