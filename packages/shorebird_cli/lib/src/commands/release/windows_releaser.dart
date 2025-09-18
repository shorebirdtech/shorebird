import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/windows/windows_app_version.dart';
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
  String get artifactDisplayName => 'Windows app';

  @override
  Future<void> assertArgsAreValid() async {
    if (argResults.wasParsed('release-version')) {
      logger.err(
        '''
The "--release-version" flag is only supported for aar and ios-framework releases.
        
To change the version of this release, change your app's version in your pubspec.yaml.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }
  }

  @override
  Version? get minimumFlutterVersion => minimumSupportedWindowsFlutterVersion;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.windowsCommandValidators,
        supportedOperatingSystems: {Platform.windows},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() {
    return artifactBuilder.buildWindowsApp(
      target: target,
      args: argResults.forwardedArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) {
    // Determines the Windows app version by selecting the application
    // executable from the release directory and reading its ProductVersion via
    // PowerShell. Prefers a match on the pubspec name; falls back to the first
    // .exe when no match is found.
    final dir = releaseArtifactRoot as Directory;
    final projectName = shorebirdEnv.getPubspecYaml()?.name;
    return getWindowsAppVersionFromDir(
      dir,
      projectNameHint: projectName,
      logTag: 'windows_releaser',
    );
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    final releaseDir = artifactManager.getWindowsReleaseDirectory();

    if (!releaseDir.existsSync()) {
      logger.err('No release directory found at ${releaseDir.path}');
      throw ProcessExit(ExitCode.software.code);
    }

    final zippedRelease = await releaseDir.zipToTempFile();

    await codePushClientWrapper.createWindowsReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      projectRoot: projectRoot.path,
      releaseZipPath: zippedRelease.path,
    );
  }

  @override
  String get postReleaseInstructions =>
      '''

Windows executable created at ${artifactManager.getWindowsReleaseDirectory().path}.
''';
}
