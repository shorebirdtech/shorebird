import 'dart:io';

import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';

/// {@template linux_releaser}
/// Functions to create a linux release.
/// {@endtemplate}
class LinuxReleaser extends Releaser {
  /// {@macro linux_releaser}
  LinuxReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.linux;

  @override
  String get supplementPlatformSubdir => 'linux';

  @override
  String get supplementArtifactArch => 'linux_supplement';

  @override
  String get artifactDisplayName => 'Linux app';

  @override
  Future<void> assertArgsAreValid() async =>
      assertReleaseVersionFlagNotProvided();

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: doctor.linuxCommandValidators,
    supportedOperatingSystems: {NativePlatform.linux},
  );

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    await runReleaseBuild(
      (buildArgs, base64PublicKey) => artifactBuilder.buildLinuxApp(
        target: target,
        args: buildArgs,
        base64PublicKey: base64PublicKey,
      ),
    );

    return artifactManager.linuxBundleDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async => linux.versionFromLinuxBundle(
    bundleRoot: releaseArtifactRoot as Directory,
  );

  @override
  String get postReleaseInstructions =>
      '''

Linux release created at ${artifactManager.linuxBundleDirectory.path}.
''';

  @override
  Future<List<ReleaseArtifactUpload>> prepareReleaseArtifacts({
    required Directory stagingDirectory,
  }) {
    return codePushClientWrapper.prepareLinuxReleaseArtifacts(
      bundle: artifactManager.linuxBundleDirectory,
      stagingDirectory: stagingDirectory,
    );
  }

}
