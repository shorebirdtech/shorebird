import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template enterprises_get_command}
/// `shorebird enterprises get <enterprise-id>`
/// Show an enterprise's name and domains.
/// {@endtemplate}
class EnterprisesGetCommand extends ShorebirdCommand
    with EnterpriseScopedCommand {
  /// {@macro enterprises_get_command}
  EnterprisesGetCommand();

  @override
  String get name => 'get';

  @override
  String get invocation => 'shorebird enterprises get <enterprise-id>';

  @override
  String get description =>
      "Shows an enterprise's name and domains. Needs an owner or admin of "
      'the enterprise.\n\n'
      'Example output:\n'
      '  Acme (id: 7)\n'
      '  Domains: acme.com, acme.dev\n\n'
      '${ShorebirdCommand.jsonHint('shorebird enterprises get 7 --json')}';

  @override
  Future<int> run() async {
    final rest = results.rest;
    if (rest.length > 1) {
      return reportError(
        message: 'Pass one enterprise id: shorebird enterprises get 7.',
      );
    }
    // Reading one enterprise widens nothing, so your only one is a safe
    // default, as `orgs get` defaults to your only organization.
    final (:membership, :errorCode) = await resolveEnterprise(
      enterpriseId: rest.firstOrNull,
      defaultToOnly: true,
    );
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
      ..info('Domains: ${domains.isEmpty ? 'none' : domains.join(', ')}');
    return ExitCode.success.code;
  }
}
