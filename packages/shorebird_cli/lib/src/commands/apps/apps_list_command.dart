import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template apps_list_command}
/// `shorebird apps list`
/// List the apps the current user has access to.
/// {@endtemplate}
class AppsListCommand extends ShorebirdCommand with EnterpriseScopedCommand {
  /// {@macro apps_list_command}
  AppsListCommand() {
    addEnterpriseScopeFlag(
      help:
          'List every app in every organization of your enterprise. Needs '
          'an owner or admin of the enterprise.',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      'Lists the apps you have access to.\n\n'
      'Example output (space-separated: app_id  display_name  '
      'latest_release_version  latest_patch_number):\n'
      '  01H...  Acme Mobile  1.2.3  4\n'
      '  01J...  Acme Internal  -  -\n\n'
      '"-" indicates no release or patch has been published yet.\n\n'
      'With --enterprise, lists every app in the enterprise '
      '(space-separated: app_id  display_name  organization_id  '
      'organization_name):\n'
      '  01H...  Acme Mobile  42  Mobile\n\n'
      '${ShorebirdCommand.jsonHint('shorebird apps list --json')}';

  @override
  Future<int> run() async {
    if (enterpriseScope) return _listEnterpriseApps();
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final List<AppMetadata> apps;
    final fetchError = await guardApiCall(
      () async => apps = await codePushClientWrapper.getApps(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch apps.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'apps': [
          for (final app in apps)
            {
              'app_id': app.appId,
              'display_name': app.displayName,
              'latest_release_version': app.latestReleaseVersion,
              'latest_patch_number': app.latestPatchNumber,
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (apps.isEmpty) {
      logger.info('No apps found.');
      return ExitCode.success.code;
    }

    for (final app in apps) {
      logger.info(
        '${app.appId}  ${lightCyan.wrap(app.displayName)}  '
        '${app.latestReleaseVersion ?? '-'}  '
        '${app.latestPatchNumber ?? '-'}',
      );
    }

    return ExitCode.success.code;
  }

  Future<int> _listEnterpriseApps() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final List<EnterpriseApp> apps;
    final fetchError = await guardApiCall(
      () async => apps = await codePushClientWrapper.getEnterpriseApps(
        enterpriseId: enterprise.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the apps of enterprise ${enterprise.id}.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'apps': [
          for (final app in apps)
            {
              'app_id': app.appId,
              'display_name': app.appDisplayName,
              'organization_id': app.organizationId,
              'organization_name': app.organizationName,
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (apps.isEmpty) {
      logger.info('"${enterprise.name}" has no apps.');
      return ExitCode.success.code;
    }
    for (final app in apps) {
      logger.info(
        '${app.appId}  ${lightCyan.wrap(app.appDisplayName)}  '
        '${app.organizationId}  ${app.organizationName}',
      );
    }
    return ExitCode.success.code;
  }
}
