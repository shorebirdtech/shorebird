import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template windows_releaser}
/// Functions to create a Windows release.
/// {@endtemplate}
class WindowsReleaser extends Releaser {
  /// {@macro windows_releaser}
  WindowsReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.windows;

  @override
  String get supplementPlatformSubdir => 'windows';

  @override
  String get supplementArtifactArch =>
      windowsSupplementArtifactArch(windowsTargetArch);

  @override
  Version get minimumFlutterVersion => windowsTargetArch == Arch.arm64
      ? minimumSupportedWindowsArm64FlutterVersion
      : super.minimumFlutterVersion;

  /// A release built on one architecture can take the other's build: an app
  /// shipped for x64 and arm64 is released once on each kind of machine.
  @override
  Future<bool> addsToActiveRelease(Release release) async {
    final existing = await codePushClientWrapper.maybeGetReleaseArtifact(
      appId: release.appId,
      releaseId: release.id,
      arch: windowsReleaseArtifactArch(windowsTargetArch),
      platform: releaseType.releasePlatform,
    );
    return existing == null;
  }

  @override
  String get artifactDisplayName => 'Windows app';

  @override
  Future<void> assertArgsAreValid() async =>
      assertReleaseVersionFlagNotProvided();

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: doctor.windowsCommandValidators,
    supportedOperatingSystems: {NativePlatform.windows},
  );

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    return runReleaseBuild(
      (buildArgs, base64PublicKey) => artifactBuilder.buildWindowsApp(
        target: target,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
      ),
    );
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) {
    final executable = windows.findExecutable(
      releaseDirectory: releaseArtifactRoot as Directory,
      projectName: shorebirdEnv.getPubspecYaml()!.name,
    );
    return powershell.getProductVersion(executable);
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final releaseDir = artifactManager.getWindowsReleaseDirectory();

    if (!releaseDir.existsSync()) {
      throw CommandError(
        message: 'No release directory found at ${releaseDir.path}.',
        hint: 'Re-run with --verbose to see the build output.',
        exitCode: ExitCode.software,
      );
    }

    await codePushClientWrapper.createWindowsReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      releaseDirectory: releaseDir,
      arch: windowsReleaseArtifactArch(windowsTargetArch),
      signing: signing,
    );
  }

  @override
  String get postReleaseInstructions =>
      '''

Windows executable created at ${artifactManager.getWindowsReleaseDirectory().path}.
''';
}
