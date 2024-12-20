import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_android_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
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

  /// The architectures to build for.
  Set<Arch> get architectures => (argResults['target-platform'] as List<String>)
      .map(
        (platform) => AndroidArch.availableAndroidArchs
            .firstWhere((arch) => arch.targetPlatformCliArg == platform),
      )
      .toSet();

  /// Whether to generate an APK in addition to the AAB.
  late bool generateApk = argResults['artifact'] as String == 'apk';

  /// Whether to split the APK per ABI. This is not something we support, but
  /// we check for this to provide a more helpful error message.
  late bool splitApk = argResults['split-per-abi'] == true;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<void> assertArgsAreValid() async {
    argResults.assertAbsentOrValidPublicKey();

    if (argResults.wasParsed('release-version')) {
      logger.err(
        '''
The "--release-version" flag is only supported for aar and ios-framework releases.
        
To change the version of this release, change your app's version in your pubspec.yaml.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    if (generateApk && splitApk) {
      logger
        ..err(
          'Shorebird does not support the split-per-abi option at this time',
        )
        ..info(
          '''
Split APKs are each given a different release version than what is specified in the pubspec.yaml.

See ${link(uri: Uri.parse('https://github.com/flutter/flutter/issues/39817'))} for more information about this issue.
Please comment and upvote ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1141'))} if you would like shorebird to support this.''',
        );
      throw ProcessExit(ExitCode.unavailable.code);
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    final architectures = (argResults['target-platform'] as List<String>)
        .map(
          (platform) => AndroidArch.availableAndroidArchs
              .firstWhere((arch) => arch.targetPlatformCliArg == platform),
        )
        .toSet();

    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildAppBundleProgress = logger.detailProgress(
      'Building app bundle with Flutter $flutterVersionString',
    );

    final File aab;

    final base64PublicKey = argResults.encodedPublicKey;

    try {
      aab = await artifactBuilder.buildAppBundle(
        flavor: flavor,
        target: target,
        targetPlatforms: architectures,
        args: argResults.forwardedArgs,
        base64PublicKey: base64PublicKey,
        buildProgress: buildAppBundleProgress,
      );
    } on ArtifactBuildException catch (e) {
      buildAppBundleProgress.fail(e.message);
      throw ProcessExit(ExitCode.software.code);
    }

    buildAppBundleProgress.complete();

    if (generateApk) {
      final buildApkProgress =
          logger.progress('Building APK with Flutter $flutterVersionString');
      try {
        await artifactBuilder.buildApk(
          flavor: flavor,
          target: target,
          targetPlatforms: architectures,
          args: argResults.forwardedArgs,
          base64PublicKey: base64PublicKey,
        );
      } on ArtifactBuildException catch (e) {
        buildApkProgress.fail(e.message);
        throw ProcessExit(ExitCode.software.code);
      }
      buildApkProgress.complete();
    }

    return aab;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final releaseVersionProgress =
        logger.progress('Determining release version');
    final String releaseVersion;

    try {
      releaseVersion =
          await shorebirdAndroidArtifacts.extractReleaseVersionFromAppBundle(
        releaseArtifactRoot.path,
      );
      releaseVersionProgress.complete('Release version: $releaseVersion');
    } on Exception catch (error) {
      releaseVersionProgress.fail('$error');
      throw ProcessExit(ExitCode.software.code);
    }

    return releaseVersion;
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required String appId,
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
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async =>
      metadata.copyWith(generatedApks: generateApk);

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
}
