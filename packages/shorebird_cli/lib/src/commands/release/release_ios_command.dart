import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/ios.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_version_manager.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_ios_command}
/// `shorebird release ios-alpha`
/// Create new app releases for iOS.
/// {@endtemplate}
class ReleaseIosCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  /// {@macro release_ios_command}
  ReleaseIosCommand({
    IpaReader? ipaReader,
  }) : _ipaReader = ipaReader ?? IpaReader() {
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

  final IpaReader _ipaReader;

  @override
  String get description => '''
Builds and submits your iOS app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'ios-alpha';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    showiOSStatusWarning();

    const releasePlatform = ReleasePlatform.ios;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final buildProgress = logger.progress('Building release');
    try {
      await buildIpa(flavor: flavor, target: target);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build IPA: ${error.message}');
      return ExitCode.software.code;
    } on BuildException catch (error) {
      buildProgress.fail('Failed to build IPA');
      logger.err(error.message);
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final releaseVersionProgress = logger.progress('Getting release version');
    final iosBuildDir = p.join(Directory.current.path, 'build', 'ios');
    final ipaPath = p.join(
      iosBuildDir,
      'ipa',
      '${getIpaName()}.ipa',
    );
    final runnerPath = p.join(
      iosBuildDir,
      'archive',
      'Runner.xcarchive',
      'Products',
      'Applications',
      'Runner.app',
    );
    String releaseVersion;
    try {
      final ipa = _ipaReader.read(ipaPath);
      releaseVersion = ipa.versionNumber;
    } catch (error) {
      releaseVersionProgress.fail(
        'Failed to determine release version: $error',
      );
      return ExitCode.software.code;
    }

    releaseVersionProgress.complete();

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

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(releasePlatform.name)}''',
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
      shorebirdFlutterRevision =
          await shorebirdVersionManager.getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
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
        flutterRevision: shorebirdFlutterRevision,
        platform: releasePlatform,
      );
    }

    final relativeIpaPath = p.relative(ipaPath);

    await codePushClientWrapper.createIosReleaseArtifacts(
      appId: app.appId,
      releaseId: release.id,
      ipaPath: ipaPath,
      runnerPath: runnerPath,
    );

    await codePushClientWrapper.updateReleaseStatus(
      appId: app.appId,
      releaseId: release.id,
      platform: releasePlatform,
      status: ReleaseStatus.active,
    );

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to upload the ipa to App Store Connect.
${lightCyan.wrap(relativeIpaPath)}

To upload to the App Store either:
    1. Drag and drop the "$relativeIpaPath" bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784)
    2. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f $relativeIpaPath --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
''');

    return ExitCode.success.code;
  }
}
