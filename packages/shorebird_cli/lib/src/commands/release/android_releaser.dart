import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template android_releaser}
/// Functions to create an Android release.
/// {@endtemplate}
class AndroidReleaser extends Releaser {
  /// {@macro android_releaser}
  AndroidReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.android;

  @override
  String get supplementPlatformSubdir => 'android';

  @override
  String get supplementArtifactArch => 'android_supplement';

  @override
  String get artifactDisplayName => 'Android app bundle';

  /// The architectures to build for.
  Set<Arch> get architectures => AndroidArch.fromTargetPlatformArgs(
    argResults['target-platform'] as List<String>,
  );

  /// Whether to generate an APK in addition to the AAB.
  late bool generateApk = argResults['artifact'] as String == 'apk';

  /// Whether to split the APK per ABI. This is not something we support, but
  /// we check for this to provide a more helpful error message.
  late bool splitApk = argResults['split-per-abi'] == true;

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: doctor.androidCommandValidators,
  );

  @override
  Future<void> assertArgsAreValid() async {
    assertReleaseVersionFlagNotProvided();

    if (generateApk && splitApk) {
      throw CommandError(
        message:
            'Shorebird does not support --split-per-abi: each split APK gets '
            'a different version than the one in your pubspec.yaml.',
        hint:
            'Re-run without --split-per-abi. To ask for support, upvote '
            'https://github.com/shorebirdtech/shorebird/issues/1141.',
        exitCode: ExitCode.unavailable,
      );
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    // The APK is built after the obfuscation map check, with the same
    // arguments as the AAB.
    final (aab, buildArgs, base64PublicKey) = await runReleaseBuild(
      (buildArgs, base64PublicKey) async => (
        await artifactBuilder.buildAppBundle(
          flavor: flavor,
          target: target,
          targetPlatforms: architectures,
          args: buildArgs,
          base64PublicKey: base64PublicKey,
        ),
        buildArgs,
        base64PublicKey,
      ),
    );

    if (generateApk) {
      logger.info('Building APK');
      await artifactBuilder.buildApk(
        flavor: flavor,
        target: target,
        targetPlatforms: architectures,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
      );
    }

    return aab;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final releaseVersionProgress = logger.progress(
      'Determining release version',
    );
    final String releaseVersion;

    try {
      releaseVersion = await shorebirdAndroidArtifacts
          .extractReleaseVersionFromAppBundle(releaseArtifactRoot.path);
      releaseVersionProgress.complete('Release version: $releaseVersion');
      _explainVersionNameChange(releaseVersion);
    } on Exception catch (error) {
      releaseVersionProgress.fail();
      throw CommandError(
        message:
            'Unable to read the release version from the app bundle: '
            '$error',
        exitCode: ExitCode.software,
      );
    }

    return releaseVersion;
  }

  /// Explains, when Gradle changed the version name Flutter built with (a
  /// flavor's `versionNameSuffix`, or a `versionName` override), that this
  /// release won't be the same Shorebird release as an iOS build of the same
  /// version, which customers otherwise find out from the console.
  void _explainVersionNameChange(String releaseVersion) {
    final flutterBuildName =
        argResults['build-name'] as String? ??
        shorebirdEnv.getPubspecYaml()?.version?.toString().split('+').first;
    if (flutterBuildName == null) return;
    final [versionName, ...versionCode] = releaseVersion.split('+');
    if (versionName == flutterBuildName) return;
    final iosVersion = [flutterBuildName, ...versionCode].join('+');
    logger.info(
      '''Android's version name $versionName is not $flutterBuildName, the version Flutter built with: android/app/build.gradle changes it (versionNameSuffix or versionName). So this release is not the same Shorebird release as an iOS build of this version ($iosVersion), and each needs its own patches. To share one release across platforms, remove the suffix.''',
    );
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required String appId,
    required Release release,
  }) async {
    final aabFile = shorebirdAndroidArtifacts.findAab(
      project: projectRoot,
      flavor: flavor,
    );
    await codePushClientWrapper.createAndroidReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      projectRoot: projectRoot.path,
      aabPath: aabFile.path,
      platform: releaseType.releasePlatform,
      architectures: architectures,
      flavor: flavor,
      signing: signing,
    );
  }

  @override
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async => metadata.copyWith(generatedApks: generateApk);

  @override
  String get postReleaseInstructions {
    final aabFile = shorebirdAndroidArtifacts.findAab(
      project: projectRoot,
      flavor: flavor,
    );

    final String apkText;
    if (generateApk) {
      final apkFile = shorebirdAndroidArtifacts.findApk(
        project: projectRoot,
        flavor: flavor,
      );
      apkText =
          '''

Or distribute the apk:
${lightCyan.wrap(apkFile.path)}
''';
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
}
