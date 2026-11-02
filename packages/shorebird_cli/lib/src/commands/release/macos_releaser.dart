import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/apple_build_helpers.dart';
import 'package:shorebird_cli/src/commands/release/apple_releaser_mixin.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template macos_releaser}
/// Functions to build and publish a macOS release.
/// {@endtemplate}
class MacosReleaser extends Releaser with AppleReleaserMixin {
  /// {@macro macos_releaser}
  MacosReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  @override
  String get supplementPlatformSubdir => 'macos';

  @override
  String get supplementArtifactArch => 'macos_supplement';

  @override
  String get artifactDisplayName => 'macOS app';

  @override
  List<Validator> get applePlatformValidators => doctor.macosCommandValidators;

  @override
  Future<void> assertArgsAreValid() async {
    assertReleaseVersionFlagNotProvided();
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    if (!argResults.appleCodesign) {
      logger
        ..info(
          '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
        )
        ..warn(
          '''shorebird preview will not work for releases created with "--no-codesign". However, you can still preview your app by signing the generated .xcarchive in Xcode.''',
        );
    }

    await runReleaseBuild(
      (buildArgs, base64PublicKey) => artifactBuilder.buildMacos(
        codesign: argResults.appleCodesign,
        flavor: flavor,
        target: target,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
        ddMaxBytes: ddMaxBytes,
      ),
    );

    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      throw CommandError(
        message: 'Unable to find the .app directory in the macOS build output.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    return appDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async => readReleaseVersionFromInfoPlist(
    File(p.join(releaseArtifactRoot.path, 'Contents', 'Info.plist')),
    hint: 'Re-run with --verbose to see the build output.',
  );

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      throw CommandError(
        message: 'Unable to find the .app directory in the macOS build output.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    await codePushClientWrapper.createMacosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appPath: appDirectory.path,
      podfileLockHash: shorebirdEnv.macosPodfileLockHash,
      signing: signing,
    );
  }

  @override
  String get postReleaseInstructions =>
      '''

macOS app created at ${artifactManager.getMacOSAppDirectory(flavor: flavor)!.path}.
${shorebirdArtifacts.macosPatchesSurviveResigning ? '' : _resigningNote}''';

  String get _resigningNote =>
      '''

${styleBold.wrap('Note:')} Patches to this release may fail to install after the app is re-signed (Developer ID or a Mac App Store .pkg). Release with Flutter 3.47.7 or newer to avoid this. See ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/3223'))} for more information.
''';
}
