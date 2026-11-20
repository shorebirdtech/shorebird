import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

const _includeArchivedArgName = 'include-archived';

/// {@template apps_list_command}
/// `shorebird apps list`
/// List the apps the current user has access to.
/// {@endtemplate}
class AppsListCommand extends ShorebirdCommand with EnterpriseScopedCommand {
  /// {@macro apps_list_command}
  ///
  /// With [enterpriseRoute], it is `shorebird enterprise apps list`.
  AppsListCommand({bool enterpriseRoute = false}) {
    isEnterpriseRoute = enterpriseRoute;
    // The enterprise listing comes from an endpoint that neither takes
    // includeArchived nor says when an app was archived.
    if (!enterpriseRoute) {
      argParser.addFlag(
        _includeArchivedArgName,
        negatable: false,
        help: 'List archived apps too, with the date each was archived.',
      );
    }
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      isEnterpriseRoute ? _enterpriseDescription : _organizationDescription;

  String get _enterpriseDescription =>
      'Lists every app in every organization of your enterprise. Needs an '
      'owner or admin of the enterprise.\n\n'
      'Example output (space-separated: app_id  display_name  '
      'organization_id  organization_name):\n'
      '  01H...  Acme Mobile  42  Mobile\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird enterprise apps list --json',
      )}';

  String get _organizationDescription =>
      'Lists the apps you have access to.\n\n'
      'Example output (space-separated: app_id  display_name  '
      'latest_release_version  latest_patch_number):\n'
      '  01H...  Acme Mobile  1.2.3  4\n'
      '  01J...  Acme Internal  -  -\n\n'
      '"-" indicates no release or patch has been published yet.\n\n'
      'Archived apps are left out. With --include-archived they are listed '
      'too, with a trailing archived column: the UTC date the app was '
      'archived, or "-" when it is not archived.\n\n'
      'For every app in your enterprise, run '
      '`shorebird enterprise apps list`.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird apps list --json')}';

  @override
  Future<int> run() async {
    final scopeError = rejectConflictingScope();
    if (scopeError != null) return scopeError;
    if (isEnterpriseRoute) return _listEnterpriseApps();
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final includeArchived = results[_includeArchivedArgName] as bool;

    late final List<AppMetadata> apps;
    final fetchError = await guardApiCall(
      () async => apps = await codePushClientWrapper.getApps(
        includeArchived: includeArchived,
      ),
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
              if (includeArchived)
                'archived_at': app.archivedAt?.toUtc().toIso8601String(),
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
      final line =
          '${app.appId}  ${lightCyan.wrap(app.displayName)}  '
          '${app.latestReleaseVersion ?? '-'}  '
          '${app.latestPatchNumber ?? '-'}';
      logger.info(
        includeArchived ? '$line  ${_archivedDate(app.archivedAt)}' : line,
      );
    }

    return ExitCode.success.code;
  }

  /// [archivedAt]'s UTC calendar date, or `-` when the app is not archived.
  String _archivedDate(DateTime? archivedAt) => archivedAt == null
      ? '-'
      : archivedAt.toUtc().toIso8601String().substring(0, 10);

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
      message: 'Failed to fetch the apps of "${enterprise.name}".',
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
