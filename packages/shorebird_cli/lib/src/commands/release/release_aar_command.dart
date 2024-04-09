import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:io/io.dart' show copyPath;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_aar_command}
/// `shorebird release aar`
/// Create new Android archive releases.
/// {@endtemplate}
class ReleaseAarCommand extends ShorebirdCommand
    with
        ShorebirdBuildMixin,
        ShorebirdReleaseVersionMixin,
        ShorebirdArtifactMixin {
  /// {@macro release_aar_command}
  ReleaseAarCommand({
    UnzipFn? unzipFn,
  }) : _unzipFn = unzipFn ?? extractFileToDisk {
    argParser
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the Android app that is using this module.''',
        mandatory: true,
      )
      // `flutter build aar` defaults to a build number of 1.0, so we do the
      // same.
      ..addOption(
        'build-number',
        help: 'The build number of the aar',
        defaultsTo: '1.0',
      )
      ..addOption(
        'flutter-version',
        help: 'The Flutter version to use when building the app (e.g: 3.16.3).',
      )
      ..addMultiOption(
        'target-platform',
        help: 'The target platform(s) for which the app is compiled.',
        defaultsTo: Arch.values.map((arch) => arch.targetPlatformCliArg),
        allowed: Arch.values.map((arch) => arch.targetPlatformCliArg),
      );
  }

  @override
  String get name => 'aar';

  @override
  String get description => '''
Builds and submits your Android archive to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  final UnzipFn _unzipFn;

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    if (shorebirdEnv.androidPackageName == null) {
      logger.err('Could not find androidPackage in pubspec.yaml.');
      return ExitCode.config.code;
    }

    const releasePlatform = ReleasePlatform.android;
    final buildNumber = results['build-number'] as String;
    final releaseVersion = results['release-version'] as String;
    final flutterVersion = results['flutter-version'] as String?;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId();
    final app = await codePushClientWrapper.getApp(appId: appId);
    final architectures = (results['target-platform'] as List<String>)
        .map(
          (platform) => AndroidArch.availableAndroidArchs
              .firstWhere((arch) => arch.targetPlatformCliArg == platform),
        )
        .toSet();

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (existingRelease != null) {
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: releasePlatform,
      );
    }

    var flutterRevisionForRelease = shorebirdEnv.flutterRevision;
    if (flutterVersion != null) {
      final String? revision;
      try {
        revision = await shorebirdFlutter.getRevisionForVersion(
          flutterVersion,
        );
      } catch (error) {
        logger.err(
          '''
Unable to determine revision for Flutter version: $flutterVersion.
$error''',
        );
        return ExitCode.software.code;
      }

      if (revision == null) {
        final openIssueLink = link(
          uri: Uri.parse(
            'https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=feature&projects=&template=feature_request.md&title=feat%3A+',
          ),
          message: 'open an issue',
        );
        logger.err('''
Version $flutterVersion not found. Please $openIssueLink to request a new version.
Use `shorebird flutter versions list` to list available versions.
''');
        return ExitCode.software.code;
      }

      flutterRevisionForRelease = revision;
    }

    try {
      await shorebirdFlutter.installRevision(
        revision: flutterRevisionForRelease,
      );
    } catch (_) {
      return ExitCode.software.code;
    }

    final releaseFlutterShorebirdEnv = shorebirdEnv.copyWith(
      flutterRevisionOverride: flutterRevisionForRelease,
    );

    return await runScoped(
      () async {
        final flutterVersionString =
            await shorebirdFlutter.getVersionAndRevision();

        final buildProgress = logger.progress(
          'Building release with Flutter $flutterVersionString',
        );

        try {
          await buildAar(
            buildNumber: buildNumber,
            targetPlatforms: architectures,
          );
        } on ProcessException catch (error) {
          buildProgress.fail('Failed to build: ${error.message}');
          return ExitCode.software.code;
        }
        buildProgress.complete();

        final archNames = architectures.map((arch) => arch.name);
        final summary = [
          '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
          '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
          '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
          '🐦 Flutter Version: ${lightCyan.wrap(flutterVersionString)}',
        ];

        logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

${summary.join('\n')}
''');

        if (shorebirdEnv.canAcceptUserInput) {
          final confirm = logger.confirm('Would you like to continue?');

          if (!confirm) {
            logger.info('Aborting.');
            return ExitCode.success.code;
          }
        }

        final Release release;
        if (existingRelease != null) {
          release = existingRelease;
          await codePushClientWrapper.updateReleaseStatus(
            appId: appId,
            releaseId: release.id,
            platform: releasePlatform,
            status: ReleaseStatus.draft,
          );
        } else {
          release = await codePushClientWrapper.createRelease(
            appId: appId,
            version: releaseVersion,
            flutterRevision: shorebirdEnv.flutterRevision,
            platform: releasePlatform,
          );
        }

        // Copy release AAR to a new directory to avoid overwriting with
        // subsequent patch builds.
        final sourceLibraryDirectory = Directory(aarLibraryPath);
        final targetLibraryDirectory = Directory(
          p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
        );
        await copyPath(
          sourceLibraryDirectory.path,
          targetLibraryDirectory.path,
        );

        final extractAarProgress = logger.progress('Creating artifacts');
        final extractedAarDir = await extractAar(
          packageName: shorebirdEnv.androidPackageName!,
          buildNumber: buildNumber,
          unzipFn: _unzipFn,
        );
        extractAarProgress.complete();

        await codePushClientWrapper.createAndroidArchiveReleaseArtifacts(
          appId: app.appId,
          releaseId: release.id,
          platform: releasePlatform,
          aarPath: aarArtifactPath(
            packageName: shorebirdEnv.androidPackageName!,
            buildNumber: buildNumber,
          ),
          extractedAarDir: extractedAarDir,
          architectures: architectures,
        );

        await codePushClientWrapper.updateReleaseStatus(
          appId: app.appId,
          releaseId: release.id,
          platform: releasePlatform,
          status: ReleaseStatus.active,
          metadata: UpdateReleaseMetadata(
            releasePlatform: releasePlatform,
            flutterVersionOverride: flutterVersion,
            generatedApks: false,
            environment: BuildEnvironmentMetadata(
              operatingSystem: platform.operatingSystem,
              operatingSystemVersion: platform.operatingSystemVersion,
              shorebirdVersion: packageVersion,
              xcodeVersion: null,
            ),
          ),
        );

        logger
          ..success('\n✅ Published Release ${release.version}!')
          ..info('''

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
''');

        return ExitCode.success.code;
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }
}
