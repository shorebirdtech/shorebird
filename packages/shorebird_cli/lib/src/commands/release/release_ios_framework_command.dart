import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
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
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Release without confirmation if there are no errors.',
        negatable: false,
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
        validators: [
          ...doctor.iosCommandValidators,
          ShorebirdFlutterVersionSupportsIOSValidator(),
        ],
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

    final originalFlutterRevision = shorebirdEnv.flutterRevision;
    final switchFlutterRevision =
        flutterRevisionForRelease != originalFlutterRevision;

    if (switchFlutterRevision) {
      await shorebirdFlutter.useRevision(revision: flutterRevisionForRelease);
    }

    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildProgress = logger.progress(
      'Building iOS framework with Flutter $flutterVersionString',
    );

    try {
      await buildIosFramework();
    } catch (error) {
      buildProgress.fail('Failed to build iOS framework: $error');
      return ExitCode.software.code;
    } finally {
      if (switchFlutterRevision) {
        await shorebirdFlutter.useRevision(revision: originalFlutterRevision);
      }
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

    final force = results['force'] == true;
    final needConfirmation = !force;
    if (needConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    final Release release;
    if (existingRelease != null) {
      release = existingRelease;
    } else {
      release = await codePushClientWrapper.createRelease(
        appId: appId,
        version: releaseVersion,
        // Intentionally not using shorebirdEnv.flutterRevision here because
        // the revision may have changed for the build.
        flutterRevision: flutterRevisionForRelease,
        platform: releasePlatform,
      );
    }

    await codePushClientWrapper.createIosFrameworkReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appFrameworkPath: getAppXcframeworkPath(),
    );

    await codePushClientWrapper.updateReleaseStatus(
      appId: app.appId,
      releaseId: release.id,
      platform: releasePlatform,
      status: ReleaseStatus.active,
    );

    final relativeFrameworkDirectoryPath =
        p.relative(getAppXcframeworkDirectory().path);
    logger
      ..success('\n✅ Published Release ${release.version}!')
      ..info('''

Your next step is to include the .xcframework files in ${lightCyan.wrap(relativeFrameworkDirectoryPath)} in your iOS app.

To do this:
    1. Add the relative path to $relativeFrameworkDirectoryPath to your app's Framework Search Paths in your Xcode build settings.
    2. Embed the App.xcframework and Flutter.framework in your Xcode project.

Instructions for these steps can be found at https://docs.flutter.dev/add-to-app/ios/project-setup#option-b---embed-frameworks-in-xcode.
''');

    return ExitCode.success.code;
  }
}
