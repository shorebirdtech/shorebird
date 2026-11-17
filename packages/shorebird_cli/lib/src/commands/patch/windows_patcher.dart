import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/archive_analysis/windows_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/patch/desktop_patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template windows_patcher}
/// Functions to create a Windows patch.
/// {@endtemplate}
class WindowsPatcher extends DesktopPatcher {
  /// {@macro windows_patcher}
  WindowsPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// Flutter builds for this machine's architecture, so the patch is for it
  /// and diffs against the release built for it.
  @override
  Arch get patchArch => windowsTargetArch;

  @override
  String get primaryReleaseArtifactArch =>
      windowsReleaseArtifactArch(patchArch);

  @override
  String? get supplementaryReleaseArtifactArch =>
      windowsSupplementArtifactArch(patchArch);

  @override
  ReleaseType get releaseType => ReleaseType.windows;

  @override
  Version? get minimumFlutterVersion => patchArch == Arch.arm64
      ? minimumSupportedWindowsArm64FlutterVersion
      : minimumSupportedWindowsFlutterVersion;

  @override
  List<Validator> get commandValidators => doctor.windowsCommandValidators;

  @override
  String get hostOperatingSystem => NativePlatform.windows;

  @override
  WindowsArchiveDiffer get archiveDiffer => const WindowsArchiveDiffer();

  /// Refuses a release with no build for this machine's architecture, such as
  /// patching on an arm64 machine a release only ever built on x64.
  @override
  Future<void> prepareForRelease({
    required String appId,
    required Release release,
  }) async {
    final artifact = await codePushClientWrapper.maybeGetReleaseArtifact(
      appId: appId,
      releaseId: release.id,
      arch: primaryReleaseArtifactArch,
      platform: releaseType.releasePlatform,
    );
    if (artifact != null) return;
    final archName = windowsBuildDirectoryName(patchArch);
    throw CommandError(
      message:
          'Release ${release.version} has no Windows $archName build to '
          'patch. Flutter builds Windows apps for the machine it runs on, so '
          'this $archName machine can only patch an $archName build.',
      hint:
          'Run `shorebird release windows` on this machine for version '
          '${release.version} first, or patch on a machine of the '
          "release's architecture.",
      exitCode: ExitCode.software,
    );
  }

  /// The release artifact is the zipped directory at
  /// `build/windows/<arch>/runner/Release`, for this machine's architecture.
  @override
  Directory get appDirectory => artifactManager.getWindowsReleaseDirectory();

  @override
  List<String> get dartLibraryPathSegments => const ['data', 'app.so'];

  @override
  Future<Directory> buildApp({
    required List<String> args,
    String? base64PublicKey,
  }) {
    return artifactBuilder.buildWindowsApp(
      target: target,
      args: args,
      base64PublicKey: base64PublicKey,
    );
  }

  @override
  Future<String> versionFromAppDirectory(Directory appDirectory) {
    final executable = windows.findExecutable(
      releaseDirectory: appDirectory,
      projectName: shorebirdEnv.getPubspecYaml()!.name,
    );
    return powershell.getProductVersion(executable);
  }
}
