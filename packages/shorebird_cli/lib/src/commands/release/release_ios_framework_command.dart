import 'dart:io';

import 'package:io/io.dart' show copyPath;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/ios.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class ReleaseIosFrameworkCommand extends ShorebirdCommand
    with ShorebirdArtifactMixin, ShorebirdBuildMixin {
  ReleaseIosFrameworkCommand() {
    argParser
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
        mandatory: true,
      )
      ..addOption(
        'flutter-version',
        help: 'The Flutter version to use when building the app (e.g: 3.16.3).',
      );
  }

  @override
  String get name => 'ios-framework';

  @override
  List<String> get aliases => ['ios-framework-alpha'];

  @override
  String get description =>
      'Builds and submits your iOS framework to Shorebird.';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        supportedOperatingSystems: {Platform.macOS},
        validators: doctor.iosCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    const releasePlatform = ReleasePlatform.ios;
    final releaseVersion = results['release-version'] as String;
    final flutterVersion = results['flutter-version'] as String?;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId();
    final app = await codePushClientWrapper.getApp(appId: appId);

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
      if (Version.parse(flutterVersion) < minimumSupportedIosFlutterVersion) {
        logger.err(
          '''iOS releases are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.''',
        );
        return ExitCode.usage.code;
      }

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
          'Building iOS framework with Flutter $flutterVersionString',
        );

        try {
          await buildIosFramework();
        } catch (error) {
          buildProgress.fail('Failed to build iOS framework: $error');
          return ExitCode.software.code;
        }

        buildProgress.complete();

        final summary = [
          '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
          '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
          '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)}''',
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

        // Copy release xcframework to a new directory to avoid overwriting with
        // subsequent patch builds.
        final sourceLibraryDirectory = getAppXcframeworkDirectory();
        final targetLibraryDirectory = Directory(
          p.join(shorebirdEnv.getShorebirdProjectRoot()!.path, 'release'),
        );
        if (targetLibraryDirectory.existsSync()) {
          targetLibraryDirectory.deleteSync(recursive: true);
        }
        await copyPath(
          sourceLibraryDirectory.path,
          targetLibraryDirectory.path,
        );

        // Rename Flutter.xcframework to ShorebirdFlutter.xcframework to avoid
        // Xcode warning users about the .xcframework signature changing.
        Directory(
          p.join(
            targetLibraryDirectory.path,
            'Flutter.xcframework',
          ),
        ).renameSync(
          p.join(
            targetLibraryDirectory.path,
            'ShorebirdFlutter.xcframework',
          ),
        );

        final Release release;
        if (existingRelease != null) {
          release = existingRelease;
        } else {
          release = await codePushClientWrapper.createRelease(
            appId: appId,
            version: releaseVersion,
            flutterRevision: shorebirdEnv.flutterRevision,
            platform: releasePlatform,
          );
        }

        await codePushClientWrapper.createIosFrameworkReleaseArtifacts(
          appId: appId,
          releaseId: release.id,
          appFrameworkPath:
              p.join(targetLibraryDirectory.path, 'App.xcframework'),
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
              xcodeVersion: await xcodeBuild.version(),
            ),
          ),
        );

        final relativeFrameworkDirectoryPath =
            p.relative(targetLibraryDirectory.path);
        logger
          ..success('\n✅ Published Release ${release.version}!')
          ..info('''

Your next step is to add the .xcframework files found in the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your iOS app.

To do this:
    1. Add the relative path to the ${lightCyan.wrap(relativeFrameworkDirectoryPath)} directory to your app's Framework Search Paths in your Xcode build settings.
    2. Embed the App.xcframework and ShorebirdFlutter.framework in your Xcode project.

Instructions for these steps can be found at https://docs.flutter.dev/add-to-app/ios/project-setup#option-b---embed-frameworks-in-xcode.
''');

        return ExitCode.success.code;
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }
}
