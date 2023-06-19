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
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template release_aar_command}
/// `shorebird release aar`
/// Create new Android archive releases.
/// {@endtemplate}
class ReleaseAarCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin,
        ShorebirdJavaMixin,
        ShorebirdReleaseVersionMixin,
        ShorebirdArtifactMixin {
  /// {@macro release_aar_command}
  ReleaseAarCommand({
    super.validators,
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
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
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
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    if (androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

    const platformName = 'android';
    final flavor = results['flavor'] as String?;
    final buildNumber = results['build-number'] as String;
    final releaseVersion = results['release-version'] as String;
    final buildProgress = logger.progress('Building aar');

    final shorebirdYaml = ShorebirdEnvironment.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (existingRelease != null) {
      await codePushClientWrapper.ensureReleaseHasNoArtifacts(
        existingRelease: existingRelease,
        platform: platformName,
      );
    }

    try {
      await buildAar(buildNumber: buildNumber, flavor: flavor);
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
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
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

    final flutterRevisionProgress = logger.progress(
      'Fetching Flutter revision',
    );
    final String shorebirdFlutterRevision;
    try {
      shorebirdFlutterRevision = await getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
    }

    final release = existingRelease ??
        await codePushClientWrapper.createRelease(
          appId: appId,
          version: releaseVersion,
          flutterRevision: shorebirdFlutterRevision,
        );

    final extractAarProgress = logger.progress('Creating artifacts');
    final extractedAarDir = await extractAar(
      packageName: androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: _unzipFn,
    );
    extractAarProgress.complete();

    await codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
      releaseId: release.id,
      platform: platformName,
      aarPath: aarArtifactPath(
        packageName: androidPackageName!,
        buildNumber: buildNumber,
      ),
      extractedAarDir: extractedAarDir,
      architectures: architectures,
    );

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to add this module as a dependency in your app's build.gradle:
${lightCyan.wrap('''
dependencies {
  // ...
  releaseImplementation '$androidPackageName:flutter_release:$buildNumber'
  // ...
}''')}
''');

    return ExitCode.success.code;
  }
}
