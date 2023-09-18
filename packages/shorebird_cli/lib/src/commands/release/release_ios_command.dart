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
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_ios_command}
/// `shorebird release ios-alpha`
/// Create new app releases for iOS.
/// {@endtemplate}
class ReleaseIosCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdArtifactMixin {
  /// {@macro release_ios_command}
  ReleaseIosCommand() {
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
        'codesign',
        help: 'Codesign the application bundle.',
        defaultsTo: true,
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

    final codesign = results['codesign'] == true;
    if (!codesign) {
      logger
        ..info(
          '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
        )
        ..warn(
          '''shorebird preview will not work for releases created with "--no-codesign". However, you can still preview your app by signing the generated .xcarchive in Xcode.''',
        );
    }

    const releasePlatform = ReleasePlatform.ios;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final buildProgress = logger.progress('Building release');
    try {
      await buildIpa(codesign: codesign, flavor: flavor, target: target);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    } on BuildException catch (error) {
      buildProgress.fail('Failed to build');
      logger.err(error.message);
      return ExitCode.software.code;
    }

    buildProgress.complete();

    // Ensure the ipa was built
    final String ipaPath;
    try {
      ipaPath = getIpaPath();
    } catch (error) {
      logger.err('Could not find ipa file: $error');
      return ExitCode.software.code;
    }

    final iosBuildDir = p.join(Directory.current.path, 'build', 'ios');

    final archivePath = p.join(
      iosBuildDir,
      'archive',
      'Runner.xcarchive',
    );
    final runnerPath = p.join(
      archivePath,
      'Products',
      'Applications',
      'Runner.app',
    );
    final plistFile = File(p.join(archivePath, 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}.');
      return ExitCode.software.code;
    }

    final plist = Plist(file: plistFile);
    final String releaseVersion;
    try {
      releaseVersion = plist.versionNumber;
    } catch (error) {
      logger.err('Failed to determine release version: $error');
      return ExitCode.software.code;
    }

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

    await codePushClientWrapper.createIosReleaseArtifacts(
      appId: app.appId,
      releaseId: release.id,
      xcarchivePath: archivePath,
      runnerPath: runnerPath,
      isCodesigned: codesign,
    );

    await codePushClientWrapper.updateReleaseStatus(
      appId: app.appId,
      releaseId: release.id,
      platform: releasePlatform,
      status: ReleaseStatus.active,
    );

    logger.success('\n✅ Published Release!');

    if (codesign) {
      final relativeIpaPath = p.relative(ipaPath);
      logger.info('''

Your next step is to upload the ipa to App Store Connect.
${lightCyan.wrap(relativeIpaPath)}

To upload to the App Store either:
    1. Drag and drop the "$relativeIpaPath" bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784)
    2. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f $relativeIpaPath --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
''');
    } else {
      logger.info('''

Your next step is to submit the archive at ${lightCyan.wrap(archivePath)} to the App Store using Xcode.

You can open the archive in Xcode by running:
    ${lightCyan.wrap('open $archivePath')}

${styleBold.wrap('Make sure to uncheck "Manage Version and Build Number", or else shorebird will not work.')}
''');
    }

    return ExitCode.success.code;
  }
}
