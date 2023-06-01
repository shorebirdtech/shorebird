import 'dart:async';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template delete_releases_command}
///
/// `shorebird releases delete`
/// Delete the specified release.
/// {@endtemplate}
class DeleteReleasesCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin {
  /// {@macro delete_releases_command}
  DeleteReleasesCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  }) {
    argParser
      ..addOption(
        'version',
        help: 'The release version to delete.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when deleting releases.',
      );
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete the specified release version.';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final appId = getShorebirdYaml()!.getAppId(flavor: flavor);

    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final List<Release> releases;
    var progress = logger.progress('Fetching releases');
    try {
      releases = await codePushClient.getReleases(appId: appId);
      progress.complete('Fetched releases.');
    } catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    final versionInput = results['version'] as String? ??
        logger.prompt(
          '${lightGreen.wrap('?')} Which version would you like to delete?',
        );

    final releaseToDelete = releases.firstWhereOrNull(
      (release) => release.version == versionInput,
    );
    if (releaseToDelete == null) {
      logger.err('No release found for version "$versionInput"');
      return ExitCode.software.code;
    }

    final shouldDelete = logger.confirm(
      'Are you sure you want to delete release ${releaseToDelete.version}?',
    );
    if (!shouldDelete) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    progress = logger.progress('Deleting release');

    try {
      await codePushClient.deleteRelease(releaseId: releaseToDelete.id);
    } catch (error) {
      progress.fail('$error');
      return ExitCode.software.code;
    }

    progress.complete('Deleted release ${releaseToDelete.version}.');

    return ExitCode.success.code;
  }
}
