import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_bundle.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template upload_command}
/// `shorebird upload <bundle>`
/// Publishes a release that `shorebird release --no-upload` built and saved.
/// {@endtemplate}
class UploadCommand extends ShorebirdCommand {
  /// {@macro upload_command}
  UploadCommand();

  @override
  String get name => 'upload';

  @override
  String get invocation => 'shorebird upload <bundle>';

  @override
  String get description =>
      'Publishes a release that `shorebird release --no-upload` built.\n\n'
      '`shorebird release --no-upload` builds a release, checks it, and saves '
      'it as a bundle (a zip under build/shorebird/) instead of uploading it. '
      'This command uploads that bundle and publishes the release, exactly as '
      '`shorebird release` would have. It does not need the project or a '
      'rebuild, so a release can be built before QA or signing, or on another '
      'machine, and published once it is approved. Patches can be made for '
      'the release once it is published.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird upload build/shorebird/release-1.0.0+1-android.zip '
        '--json',
      )}';

  @override
  Future<int> run() async {
    if (results.rest.length != 1) {
      return reportError(
        message: 'Pass the path of one release bundle to upload.',
        hint:
            'Usage: $invocation. `shorebird release --no-upload` prints the '
            "bundle's path when it saves one.",
      );
    }

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final bundleFile = File(results.rest.single);
    if (!bundleFile.existsSync()) {
      return reportError(
        message: 'No file at ${bundleFile.path}.',
        hint:
            '`shorebird release --no-upload` prints the path of the bundle it '
            'saves.',
        exitCode: ExitCode.noInput.code,
      );
    }
    final extractDirectory = Directory.systemTemp.createTempSync();
    try {
      final ReleaseBundle bundle;
      final readProgress = logger.progress('Reading release bundle');
      try {
        bundle = await ReleaseBundle.extract(
          file: bundleFile,
          directory: extractDirectory,
        );
      } on ReleaseBundleException catch (error) {
        readProgress.fail();
        return reportError(
          message: error.message,
          exitCode: ExitCode.data.code,
        );
      }
      readProgress.complete();
      return await _publish(bundle);
    } finally {
      extractDirectory.deleteTemporarySync();
    }
  }

  /// Creates or reuses the release [bundle] is for, uploads its artifacts and
  /// marks it active: what `shorebird release` does once it has built.
  Future<int> _publish(ReleaseBundle bundle) async {
    final appId = bundle.appId;
    final platform = bundle.platform;
    final app = await codePushClientWrapper.getApp(appId: appId);

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: bundle.releaseVersion,
    );
    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: platform,
      );
      // All artifacts of a release must be built with the same Flutter
      // revision.
      if (existingRelease.flutterRevision != bundle.flutterRevision) {
        final existingFlutter = [
          ?existingRelease.flutterVersion,
          '(${existingRelease.flutterRevision})',
        ].join(' ');
        return reportError(
          message:
              'Release ${bundle.releaseVersion} already exists, built with '
              'Flutter $existingFlutter, '
              'but this bundle was '
              'built with Flutter revision ${bundle.flutterRevision}. All '
              'platforms of a release must be built with the same Flutter '
              'revision.',
          hint:
              'Rebuild the bundle with '
              '--flutter-version=${existingRelease.flutterRevision}, or bump '
              'the release version.',
          code: JsonErrorCode.softwareError,
          exitCode: ExitCode.software.code,
        );
      }
    }

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to publish a release!'))}

📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}
${bundle.flavor == null ? '' : '🍧 Flavor: ${lightCyan.wrap(bundle.flavor)}\n'}📦 Release Version: ${lightCyan.wrap(bundle.releaseVersion)}
🕹️  Platform: ${lightCyan.wrap(platform.name)}
🐦 Flutter Revision: ${lightCyan.wrap(bundle.flutterRevision)}
''');

    final release =
        existingRelease ??
        await codePushClientWrapper.createRelease(
          appId: appId,
          version: bundle.releaseVersion,
          flutterRevision: bundle.flutterRevision,
          platform: platform,
        );
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: platform,
      status: ReleaseStatus.draft,
    );
    await codePushClientWrapper.uploadReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      artifacts: bundle.artifacts,
    );
    if (bundle.supplement case final supplement?) {
      await codePushClientWrapper.uploadReleaseArtifacts(
        appId: appId,
        releaseId: release.id,
        artifacts: [supplement],
        message: 'Uploading supplement artifacts',
      );
    }
    await codePushClientWrapper.updateReleaseStatus(
      appId: appId,
      releaseId: release.id,
      platform: platform,
      status: ReleaseStatus.active,
      metadata: bundle.metadata,
    );

    if (isJsonMode) {
      // The same shape as `shorebird release --json`, with the release as it
      // is now. Best-effort: the release is published, so a failed refresh
      // falls back to the release in hand rather than failing the run.
      Release? refreshed;
      try {
        refreshed = await codePushClientWrapper.maybeGetRelease(
          appId: appId,
          releaseVersion: bundle.releaseVersion,
        );
      } on Exception {
        refreshed = null;
      }
      emitJsonSuccess({
        'app_id': appId,
        'platforms': [platform.name],
        'releases': [(refreshed ?? release).toJson()],
      });
      return ExitCode.success.code;
    }

    final patchCommand = [
      'shorebird patch',
      '--platforms=${bundle.releaseType.cliName}',
      if (bundle.flavor case final flavor?) '--flavor=$flavor',
      if (bundle.target case final target?) '--target=$target',
      '--release-version=${bundle.releaseVersion}',
    ].join(' ');
    logger
      ..success('\n✅ Published Release ${bundle.releaseVersion}!')
      ..info(
        'To create a patch for this release, run '
        '${lightCyan.wrap(patchCommand)}',
      );
    return ExitCode.success.code;
  }
}
