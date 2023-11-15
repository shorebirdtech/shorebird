import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_android_command}
/// `shorebird release android`
/// Create new app releases for Android.
/// {@endtemplate}
class ReleaseAndroidCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdReleaseVersionMixin {
  /// {@macro release_android_command}
  ReleaseAndroidCommand() {
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
      ..addOption(
        'artifact',
        help: 'They type of artifact to generate.',
        allowed: ['aab', 'apk'],
        defaultsTo: 'aab',
        allowedHelp: {
          'aab': 'Android App Bundle',
          'apk': 'Android Package Kit',
        },
      )
      ..addFlag(
        'split-per-abi',
        help: 'Whether to split the APKs per ABIs. '
            'To learn more, see: https://developer.android.com/studio/build/configure-apk-splits#configure-abi-split',
        hide: true,
        negatable: false,
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
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    const platform = ReleasePlatform.android;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final generateApk = results['artifact'] as String == 'apk';
    final splitApk = results['split-per-abi'] == true;
    if (generateApk && splitApk) {
      logger
        ..err(
          'Shorebird does not support the split-per-abi option at this time',
        )
        ..info(
          '''
Split APKs are each given a different release version than what is specified in the pubspec.yaml.

See ${link(uri: Uri.parse('https://github.com/flutter/flutter/issues/39817'))} for more information about this issue.
Please comment and upvote ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1141'))} if you would like shorebird to support this.''',
        );
      return ExitCode.unavailable.code;
    }

    final buildProgress = logger.progress('Building release');
    try {
      await buildAppBundle(flavor: flavor, target: target);
      if (generateApk) {
        await buildApk(flavor: flavor, target: target);
      }
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final bundleDirPath = p.join(
      projectRoot.path,
      'build',
      'app',
      'outputs',
      'bundle',
    );
    final apkDirPath = p.join(
      projectRoot.path,
      'build',
      'app',
      'outputs',
      'apk',
    );
    final bundlePath = flavor != null
        ? p.join(bundleDirPath, '${flavor}Release', 'app-$flavor-release.aab')
        : p.join(bundleDirPath, 'release', 'app-release.aab');
    final apkPath = flavor != null
        ? p.join(apkDirPath, flavor, 'release', 'app-$flavor-release.apk')
        : p.join(apkDirPath, 'release', 'app-release.apk');

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
      codePushClientWrapper.ensureReleaseIsNotActive(
        release: existingRelease,
        platform: platform,
      );
    }

    final flutterVersion = await shorebirdFlutter.getVersionAndRevision();
    final archNames = architectures.keys.map((arch) => arch.name);
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.appId})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform.name)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
      '🐦 Flutter Version: ${lightCyan.wrap(flutterVersion)}',
    ];

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

${summary.join('\n')}
''');

    final force = results['force'] == true;
    final needConfirmation = !force && !shorebirdEnv.isRunningOnCI;
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
      await codePushClientWrapper.updateReleaseStatus(
        appId: appId,
        releaseId: release.id,
        platform: platform,
        status: ReleaseStatus.draft,
      );
    } else {
      release = await codePushClientWrapper.createRelease(
        appId: appId,
        version: releaseVersion,
        flutterRevision: shorebirdEnv.flutterRevision,
        platform: platform,
      );
    }

    await codePushClientWrapper.createAndroidReleaseArtifacts(
      appId: app.appId,
      releaseId: release.id,
      projectRoot: projectRoot.path,
      aabPath: bundlePath,
      platform: platform,
      architectures: architectures,
      flavor: flavor,
    );

    await codePushClientWrapper.updateReleaseStatus(
      appId: app.appId,
      releaseId: release.id,
      platform: platform,
      status: ReleaseStatus.active,
    );

    // The extra newline before and no newline after is intentional.  See
    // unit tests for testing of output.
    final apkText = generateApk
        ? '''

Or distribute the apk:
${lightCyan.wrap(apkPath)}
'''
        : '';

    logger
      ..success('\n✅ Published Release ${release.version}!')
      ..info('''

Your next step is to upload the app bundle to the Play Store:
${lightCyan.wrap(bundlePath)}
$apkText
For information on uploading to the Play Store, see:
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''');

    return ExitCode.success.code;
  }
}
