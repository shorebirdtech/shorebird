import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

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
  String get artifactDisplayName => 'Linux app';

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
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.linuxCommandValidators,
        supportedOperatingSystems: {Platform.linux},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
    }
    final flutterVersionArg = argResults['flutter-version'] as String?;
    if (flutterVersionArg != null) {
      final version = await shorebirdFlutter.resolveFlutterVersion(
        flutterVersionArg,
      );
      if (version != null && version < minimumSupportedLinuxFlutterVersion) {
        logger.err('''
Linux releases are not supported with Flutter versions older than $minimumSupportedLinuxFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''');
        throw ProcessExit(ExitCode.usage.code);
      }
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    await artifactBuilder.buildLinuxApp(
      base64PublicKey: argResults.encodedPublicKey,
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
  String get postReleaseInstructions => '''

Linux release created at ${artifactManager.linuxBundleDirectory.path}.
''';

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) => codePushClientWrapper.createLinuxReleaseArtifacts(
    appId: appId,
    releaseId: release.id,
    bundle: artifactManager.linuxBundleDirectory,
  );
}
