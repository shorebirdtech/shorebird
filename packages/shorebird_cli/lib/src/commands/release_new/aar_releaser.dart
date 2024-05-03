import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release_new/release_new_command.dart';
import 'package:shorebird_cli/src/commands/release_new/releaser.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class AarReleaser extends Releaser {
  AarReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  String get buildNumber => argResults['build-number'] as String;

  String get aarLibraryPath {
    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    return p.joinAll([
      projectRoot.path,
      'build',
      'host',
      'outputs',
      'repo',
    ]);
  }

  Set<Arch> get architectures => (argResults['target-platform'] as List<String>)
      .map(
        (platform) => AndroidArch.availableAndroidArchs
            .firstWhere((arch) => arch.targetPlatformCliArg == platform),
      )
      .toSet();

  @override
  ReleaseType get releaseType => ReleaseType.aar;

  @override
  Future<void> validatePreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      throw ReleaserException(exitCode: e.exitCode, message: null);
    }
  }

  @override
  Future<void> validateArgs() async {
    if (!argResults.wasParsed('release-version')) {
      throw ArgumentError('Missing required argument: --release-version');
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    await artifactBuilder.buildAar(
      buildNumber: buildNumber,
      targetPlatforms: architectures,
    );

    return Directory(aarLibraryPath);
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    return argResults['release-version'] as String;
  }

  @override
  String get postReleaseInstructions {
    final targetLibraryDirectory = Directory(
      p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
    );

    return '''

Your next steps:

1. Add the aar repo and Shorebird's maven url to your app's settings.gradle:

Note: The maven url needs to be a relative path from your settings.gradle file to the aar library. The code below assumes your Flutter module is in a sibling directory of your Android app.

${lightCyan.wrap('''
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
+       maven {
+           url '../${p.basename(shorebirdEnv.getShorebirdProjectRoot()!.path)}/${p.relative(targetLibraryDirectory.path)}'
+       }
+       maven {
-           url 'https://storage.googleapis.com/download.flutter.io'
+           url 'https://download.shorebird.dev/download.flutter.io'
+       }
    }
}
''')}

2. Add this module as a dependency in your app's build.gradle:
${lightCyan.wrap('''
dependencies {
  // ...
  releaseImplementation '${shorebirdEnv.androidPackageName}:flutter_release:$buildNumber'
  // ...
}''')}
''';
  }

  @override
  UpdateReleaseMetadata get releaseMetadata => UpdateReleaseMetadata(
        releasePlatform: releaseType.releasePlatform,
        flutterVersionOverride: argResults['flutter-version'] as String?,
        generatedApks: false,
        environment: BuildEnvironmentMetadata(
          operatingSystem: platform.operatingSystem,
          operatingSystemVersion: platform.operatingSystemVersion,
          shorebirdVersion: packageVersion,
          xcodeVersion: null,
        ),
      );

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final extractAarProgress = logger.progress('Creating artifacts');
    final extractedAarDir = await artifactManager.extractAar(
      packageName: shorebirdEnv.androidPackageName!,
      buildNumber: buildNumber,
      unzipFn: extractFileToDisk,
    );
    extractAarProgress.complete();

    await codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      platform: releaseType.releasePlatform,
      aarPath: ArtifactManager.aarArtifactPath(
        packageName: shorebirdEnv.androidPackageName!,
        buildNumber: buildNumber,
      ),
      extractedAarDir: extractedAarDir,
      architectures: architectures,
    );
  }
}
