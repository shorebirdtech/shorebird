import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/commands/release_new/release_pipeline.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template android_release_pipeline}
/// Functions to create an Android release.
/// {@endtemplate}
class AndroidReleasePipline extends ReleasePipeline {
  /// {@macro android_release_pipeline}
  AndroidReleasePipline({required super.argParser, required super.argResults});

  @override
  ReleaseType get releaseType => ReleaseType.android;

  Set<Arch> get architectures => (argResults['target-platform'] as List<String>)
      .map(
        (platform) => AndroidArch.availableAndroidArchs
            .firstWhere((arch) => arch.targetPlatformCliArg == platform),
      )
      .toSet();

  late bool generateApk = argResults['android-artifact'] as String == 'apk';
  late bool splitApk = argResults['split-per-abi'] == true;

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    final architectures = (argResults['target-platform'] as List<String>)
        .map(
          (platform) => AndroidArch.availableAndroidArchs
              .firstWhere((arch) => arch.targetPlatformCliArg == platform),
        )
        .toSet();

    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildAppBundleProgress = logger
        .progress('Building app bundle with Flutter $flutterVersionString');
    await artifactBuilder.buildAppBundle(
      flavor: flavor,
      target: target,
      targetPlatforms: architectures,
    );
    buildAppBundleProgress.complete();

    if (generateApk) {
      final buildApkProgress =
          logger.progress('Building APK with Flutter $flutterVersionString');
      await artifactBuilder.buildApk(
        flavor: flavor,
        target: target,
        targetPlatforms: architectures,
      );
      buildApkProgress.complete();
    }

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    try {
      return shorebirdAndroidArtifacts.findAab(
        project: projectRoot,
        flavor: flavor,
      );
    } on MultipleArtifactsFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but it generated multiple AABs in the '
        'build directory. ${error.foundArtifacts.map((e) => e.path)}',
      );
    } on ArtifactNotFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but could not find the AAB in the build directory. '
        'Expected to find ${error.artifactName}',
      );
    }
  }

  @override
  String get postReleaseInstructions {
    final aabFile = shorebirdAndroidArtifacts.findAab(
      project: projectRoot,
      flavor: flavor,
    );

    final String? apkText;
    if (generateApk) {
      final apkFile = shorebirdAndroidArtifacts.findApk(
        project: projectRoot,
        flavor: flavor,
      );
      apkText = generateApk
          ? '''

Or distribute the apk:
${lightCyan.wrap(apkFile.path)}
'''
          : '';
    } else {
      apkText = '';
    }

    return '''

Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(aabFile.path)}
$apkText
For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''';
  }

  @override
  Future<void> validatePreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      throw BuildPipelineException(exitCode: e.exitCode, message: null);
    }
  }

  @override
  Future<void> validateArgs() async {
    if (generateApk && splitApk) {
      throw BuildPipelineException(
        exitCode: ExitCode.unavailable,
        message: '''
Shorebird does not support the split-per-abi option at this time.
            
Split APKs are each given a different release version than what is specified in the pubspec.yaml.

See ${link(uri: Uri.parse('https://github.com/flutter/flutter/issues/39817'))} for more information about this issue.
Please comment and upvote ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1141'))} if you would like shorebird to support this.''',
      );
    }
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final releaseVersionProgress =
        logger.progress('Determining release version');
    final releaseVersion =
        await artifactManager.extractReleaseVersionFromAppBundle(
      releaseArtifactRoot.path,
    );
    releaseVersionProgress.complete('Release version: $releaseVersion');

    return releaseVersion;
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
  }) {
    final aabFile = shorebirdAndroidArtifacts.findAab(
      project: projectRoot,
      flavor: flavor,
    );
    return codePushClientWrapper.createAndroidReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      projectRoot: projectRoot.path,
      aabPath: aabFile.path,
      platform: releaseType.releasePlatform,
      architectures: architectures,
      flavor: flavor,
    );
  }

  @override
  UpdateReleaseMetadata get releaseMetadata => UpdateReleaseMetadata(
        releasePlatform: releaseType.releasePlatform,
        flutterVersionOverride: flutterVersionArg,
        generatedApks: generateApk,
        environment: BuildEnvironmentMetadata(
          operatingSystem: platform.operatingSystem,
          operatingSystemVersion: platform.operatingSystemVersion,
          shorebirdVersion: packageVersion,
          xcodeVersion: null,
        ),
      );
}
