import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/confirm_delete.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template releases_delete_command}
/// `shorebird releases delete`
/// Permanently delete a release, or one platform of a release.
/// {@endtemplate}
class ReleasesDeleteCommand extends ShorebirdCommand
    with AppScopedCommand, ConfirmDelete {
  /// {@macro releases_delete_command}
  ReleasesDeleteCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: 'The version of the release to delete (e.g. "1.0.0+1").',
        mandatory: true,
      )
      ..addOption(
        'platform',
        allowed: ReleasePlatform.values.map((p) => p.value),
        help:
            'Delete only this platform from the release. When omitted, the '
            'whole release is deleted.',
      );
    addConfirmDeleteOptions();
    addAppScopeOptions();
  }

  @override
  String get name => 'delete';

  @override
  String get description =>
      'Permanently deletes a release, or one platform of a release.\n\n'
      'Without --platform, the release is deleted along with every '
      "platform's artifacts and every patch belonging to it.\n\n"
      'With --platform, only that platform is removed: its release '
      'artifacts and the patch artifacts built for it. The release and its '
      'other platforms remain.\n\n'
      'This cannot be undone.\n\n'
      'In a terminal, asks for confirmation. Pass --$yesArgName to skip the '
      'prompt; it is required when not running interactively (no terminal, '
      'CI, or --json). Run "shorebird releases list" to see the versions an '
      'app has.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird releases delete --app-id <id> --release-version 1.0.0+1 '
        '--yes --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final platform = ReleasePlatform.maybeFromJson(
      results['platform'] as String?,
    );

    Release? maybeRelease;
    final fetchError = await guardApiCall(
      () async => maybeRelease = await codePushClientWrapper.maybeGetRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch releases for app "$appId".',
    );
    if (fetchError != null) return fetchError;

    final release = maybeRelease;
    if (release == null) {
      return reportError(
        message: 'No release with version "$releaseVersion" for app "$appId".',
        hint:
            'Run "shorebird releases list --app-id $appId" to see its '
            'release versions.',
      );
    }

    final releasePlatforms =
        release.platformStatuses.keys.map((p) => p.value).toList()..sort();

    if (platform != null && !release.platformStatuses.containsKey(platform)) {
      final available = releasePlatforms.isEmpty
          ? 'none'
          : releasePlatforms.join(', ');
      return reportError(
        message:
            'Release "$releaseVersion" has no ${platform.value} platform to '
            'delete.',
        hint: 'Platforms on this release: $available',
      );
    }

    final gateErrorCode = confirmDelete(
      name: releaseVersion,
      description: platform == null
          ? 'release $releaseVersion of app "$appId", including every '
                'platform and every patch'
          : 'the ${platform.value} platform of release $releaseVersion of app '
                '"$appId"',
      style: DeleteConfirmationStyle.yesNo,
    );
    if (gateErrorCode != null) return gateErrorCode;

    final deleteError = await guardApiCall(
      () => platform == null
          ? codePushClientWrapper.deleteRelease(
              appId: appId,
              releaseId: release.id,
            )
          : codePushClientWrapper.deleteReleaseArtifacts(
              appId: appId,
              releaseId: release.id,
              platform: platform,
            ),
      code: JsonErrorCode.softwareError,
      message: platform == null
          ? 'Failed to delete release "$releaseVersion".'
          : 'Failed to delete the ${platform.value} platform of release '
                '"$releaseVersion".',
    );
    if (deleteError != null) return deleteError;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'release_id': release.id,
        'release_version': releaseVersion,
        'release_deleted': platform == null,
        'platforms': platform == null ? releasePlatforms : [platform.value],
        'deleted': true,
      });
      return ExitCode.success.code;
    }

    logger.success(
      platform == null
          ? 'Deleted release "$releaseVersion".'
          : 'Deleted the ${platform.value} platform of release '
                '"$releaseVersion".',
    );
    return ExitCode.success.code;
  }
}
