import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_aar_command}
/// `shorebird release aar`
/// Create new Android archive releases.
/// {@endtemplate}
class ReleaseAarCommand extends ShorebirdCommand
    with
        ShorebirdBuildMixin,
        ShorebirdReleaseVersionMixin,
        ShorebirdArtifactMixin {
  /// {@macro release_aar_command}
  ReleaseAarCommand({
    UnzipFn? unzipFn,
  }) : _unzipFn = unzipFn ?? extractFileToDisk {
    argParser
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the Android app that is using this module.''',
        mandatory: true,
      )
      // `flutter build aar` defaults to a build number of 1.0, so we do the
      // same.
      ..addOption(
        'build-number',
        help: 'The build number of the aar',
        defaultsTo: '1.0',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Release without confirmation if there are no errors.',
        negatable: false,
      );
  }

  @override
  String get name => 'aar';

  @override
  String get description => '''
Builds and submits your Android archive to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  final UnzipFn _unzipFn;

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    if (shorebirdEnv.androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

    const platform = ReleasePlatform.android;
    final buildNumber = results['build-number'] as String;
    final releaseVersion = results['release-version'] as String;
    final buildProgress = logger.progress('Building aar');

    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId();
    final app = await codePushClientWrapper.getApp(appId: appId);

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: platform,
      );
    }

    try {
      await buildAar(buildNumber: buildNumber);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final archNames = architectures.keys.map(
      (arch) => arch.name,
    );
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform.name)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

${summary.join('\n')}
''');

    final force = results['force'] == true;
    final needConfirmation = !force;
    if (needConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    final Release release;
    if (existingRelease != null) {
      release = existingRelease;
      await codePushClientWrapper.updateReleaseStatus(
        appId: appId,
        releaseId: release.id,
        platform: platform,
        status: ReleaseStatus.draft,
      );
    } else {
      release = await codePushClientWrapper.createRelease(
        appId: appId,
        version: releaseVersion,
        flutterRevision: shorebirdEnv.flutterRevision,
        platform: platform,
      );
    }

    final extractAarProgress = logger.progress('Creating artifacts');
    final extractedAarDir = await extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: _unzipFn,
    );
    extractAarProgress.complete();

    await codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
      appId: app.appId,
      releaseId: release.id,
      platform: platform,
      aarPath: aarArtifactPath(
        packageName: shorebirdEnv.androidPackageName!,
        buildNumber: buildNumber,
      ),
      extractedAarDir: extractedAarDir,
      architectures: architectures,
    );

    await codePushClientWrapper.updateReleaseStatus(
      appId: app.appId,
      releaseId: release.id,
      platform: platform,
      status: ReleaseStatus.active,
    );

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to add this module as a dependency in your app's build.gradle:
${lightCyan.wrap('''
dependencies {
  // ...
  releaseImplementation '${shorebirdEnv.androidPackageName}:flutter_release:$buildNumber'
  // ...
}''')}
''');

    return ExitCode.success.code;
  }
}
