import 'dart:io' hide Platform;

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_artifact_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

const exportMethodArgName = 'export-method';
const exportOptionsPlistArgName = 'export-options-plist';

/// {@template release_ios_command}
/// `shorebird release ios`
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
      ..addOption(
        exportMethodArgName,
        defaultsTo: ExportMethod.appStore.argName,
        allowed: ExportMethod.values.map((e) => e.argName),
        help: 'Specify how the IPA will be distributed.',
        allowedHelp: {
          for (final method in ExportMethod.values)
            method.argName: method.description,
        },
      )
      ..addOption(
        exportOptionsPlistArgName,
        help:
            '''Export an IPA with these options. See "xcodebuild -h" for available exportOptionsPlist keys.''',
      )
      ..addOption(
        'flutter-version',
        help: 'The Flutter version to use when building the app (e.g: 3.16.3).',
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
  String get name => 'ios';

  @override
  List<String> get aliases => ['ios-alpha'];

  @override
  String get description => '''
Builds and submits your iOS app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: [
          ...doctor.iosCommandValidators,
          ShorebirdFlutterVersionSupportsIOSValidator(),
        ],
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    if (results.rest.contains('--obfuscate')) {
      // Obfuscated releases break patching, so we don't support them.
      // See https://github.com/shorebirdtech/shorebird/issues/1619
      logger
        ..err('Shorebird does not currently support obfuscation on iOS.')
        ..info(
          '''We hope to support obfuscation in the future. We are tracking this work at ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1619'))}.''',
        );
      return ExitCode.usage.code;
    }

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

    final exportPlistArg = results[exportOptionsPlistArgName] as String?;
    if (exportPlistArg != null && results.wasParsed(exportMethodArgName)) {
      logger.err(
        '''Cannot specify both --$exportMethodArgName and --$exportOptionsPlistArgName.''',
      );
      return ExitCode.usage.code;
    }

    final File? exportOptionsPlist;
    if (exportPlistArg != null) {
      exportOptionsPlist = File(exportPlistArg);
      try {
        _validateExportOptionsPlist(exportOptionsPlist);
      } catch (error) {
        logger.err('$error');
        return ExitCode.usage.code;
      }
    } else if (results.wasParsed(exportMethodArgName)) {
      final exportMethod = ExportMethod.values.firstWhere(
        (element) => element.argName == results[exportMethodArgName] as String,
      );
      exportOptionsPlist = createExportOptionsPlist(exportMethod: exportMethod);
    } else {
      exportOptionsPlist = null;
    }

    const releasePlatform = ReleasePlatform.ios;
    final flavor = results.findOption('flavor', argParser: argParser);
    final target = results.findOption('target', argParser: argParser);
    final flutterVersion = results.findOption(
      'flutter-version',
      argParser: argParser,
    );
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

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
          await buildIpa(
            codesign: codesign,
            exportOptionsPlist: exportOptionsPlist,
            flavor: flavor,
            target: target,
          );
        } on ProcessException catch (error) {
          buildProgress.fail('Failed to build: ${error.message}');
          return ExitCode.software.code;
        } on BuildException catch (error) {
          buildProgress.fail('Failed to build');
          logger.err(error.message);
          return ExitCode.software.code;
        }

        buildProgress.complete();

        final archiveDirectory = getXcarchiveDirectory();
        if (archiveDirectory == null) {
          logger.err('Unable to find .xcarchive directory');
          return ExitCode.software.code;
        }
        final archivePath = archiveDirectory.path;

        final appDirectory =
            getAppDirectory(xcarchiveDirectory: archiveDirectory);
        if (appDirectory == null) {
          logger.err('Unable to find .app directory');
          return ExitCode.software.code;
        }
        final runnerPath = appDirectory.path;

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
          logger.err(
            '''Failed to determine release version from ${plistFile.path}: $error''',
          );
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
          '🐦 Flutter Version: ${lightCyan.wrap(flutterVersionString)}',
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

        logger.success('\n✅ Published Release ${release.version}!');

        final relativeArchivePath = p.relative(archivePath);
        if (codesign) {
          // Ensure the ipa was built
          final String ipaPath;
          try {
            ipaPath = getIpaPath();
          } catch (error) {
            logger.err('Could not find ipa file: $error');
            return ExitCode.software.code;
          }

          final relativeIpaPath = p.relative(ipaPath);
          logger.info('''

Your next step is to upload your app to App Store Connect.

To upload to the App Store, do one of the following:
    1. Open ${lightCyan.wrap(relativeArchivePath)} in Xcode and use the "Distribute App" flow.
    2. Drag and drop the ${lightCyan.wrap(relativeIpaPath)} bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784).
    3. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f $relativeIpaPath --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
''');
        } else {
          logger.info('''

Your next step is to submit the archive at ${lightCyan.wrap(relativeArchivePath)} to the App Store using Xcode.

You can open the archive in Xcode by running:
    ${lightCyan.wrap('open $relativeArchivePath')}

${styleBold.wrap('Make sure to uncheck "Manage Version and Build Number", or else shorebird will not work.')}
''');
        }

        return ExitCode.success.code;
      },
      values: {
        shorebirdEnvRef.overrideWith(() => releaseFlutterShorebirdEnv),
      },
    );
  }

  /// Verifies that [exportOptionsPlistFile] exists and sets
  /// manageAppVersionAndBuildNumber to false, which prevents Xcode from
  /// changing the version number out from under us.
  ///
  /// Throws an exception if validation fails, exits normally if validation
  /// succeeds.
  void _validateExportOptionsPlist(File exportOptionsPlistFile) {
    if (!exportOptionsPlistFile.existsSync()) {
      throw Exception(
        '''Export options plist file ${exportOptionsPlistFile.path} does not exist''',
      );
    }

    final plist = Plist(file: exportOptionsPlistFile);
    if (plist.properties['manageAppVersionAndBuildNumber'] != false) {
      throw Exception(
        '''Export options plist ${exportOptionsPlistFile.path} does not set manageAppVersionAndBuildNumber to false. This is required for shorebird to work.''',
      );
    }
  }
}
