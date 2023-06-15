import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template release_android_command}
/// `shorebird release android`
/// Create new app releases for Android.
/// {@endtemplate}
class ReleaseAndroidCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin,
        ShorebirdJavaMixin,
        ShorebirdReleaseVersionMixin {
  /// {@macro release_android_command}
  ReleaseAndroidCommand({
    super.cache,
    super.validators,
  }) {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Release without confirmation if there are no errors.',
        negatable: false,
      );
  }

  @override
  String get description => '''
Builds and submits your Android app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'android';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    const platformName = 'android';
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final buildProgress = logger.progress('Building release');
    try {
      await buildAppBundle(flavor: flavor, target: target);
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final shorebirdYaml = ShorebirdEnvironment.getShorebirdYaml()!;

    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final bundleDirPath = p.join('build', 'app', 'outputs', 'bundle');
    final bundlePath = flavor != null
        ? p.join(bundleDirPath, '${flavor}Release', 'app-$flavor-release.aab')
        : p.join(bundleDirPath, 'release', 'app-release.aab');

    final String releaseVersion;
    final detectReleaseVersionProgress = logger.progress(
      'Detecting release version',
    );
    try {
      releaseVersion = await extractReleaseVersionFromAppBundle(bundlePath);
      detectReleaseVersionProgress.complete();
    } catch (error) {
      detectReleaseVersionProgress.fail('$error');
      return ExitCode.software.code;
    }

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (existingRelease != null) {
      logger.err(
        '''
It looks like you have an existing release for version ${lightCyan.wrap(releaseVersion)}.
Please bump your version number and try again.''',
      );
      return ExitCode.software.code;
    }

    final archNames = architectures.keys.map(
      (arch) => arch.name,
    );
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platformName)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
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

    final flutterRevisionProgress = logger.progress(
      'Fetching Flutter revision',
    );
    final String shorebirdFlutterRevision;
    try {
      shorebirdFlutterRevision = await getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
    }

    final release = await codePushClientWrapper.createRelease(
      appId: appId,
      version: releaseVersion,
      flutterRevision: shorebirdFlutterRevision,
    );

    await codePushClientWrapper.createAndroidReleaseArtifacts(
      releaseId: release.id,
      aabPath: bundlePath,
      platform: platformName,
      architectures: architectures,
      flavor: flavor,
    );

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to upload the app bundle to the Play Store.
${lightCyan.wrap(bundlePath)}

See the following link for more information:    
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''');

    return ExitCode.success.code;
  }
}
