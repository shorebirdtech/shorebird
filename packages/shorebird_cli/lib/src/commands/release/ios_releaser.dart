import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/releaser.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/ios.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template ios_releaser}
/// Functions to build and publish an iOS release.
/// {@endtemplate}
class IosReleaser extends Releaser {
  /// {@macro ios_releaser}
  IosReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  Future<void> assertArgsAreValid() async {
    if (argResults.rest.contains('--obfuscate')) {
      // Obfuscated releases break patching, so we don't support them.
      // See https://github.com/shorebirdtech/shorebird/issues/1619
      logger
        ..err('Shorebird does not currently support obfuscation on iOS.')
        ..info(
          '''We hope to support obfuscation in the future. We are tracking this work at ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1619'))}.''',
        );
      exit(ExitCode.unavailable.code);
    }
  }

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      exit(e.exitCode.code);
    }

    final flutterVersionArg = argResults['flutter-version'] as String?;
    if (flutterVersionArg != null) {
      if (Version.parse(flutterVersionArg) <
          minimumSupportedIosFlutterVersion) {
        logger.err(
          '''iOS releases are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.''',
        );
        exit(ExitCode.usage.code);
      }
    }
  }

  @override
  Future<FileSystemEntity> buildReleaseArtifacts() async {
    if (!codesign) {
      logger
        ..info(
          '''Building for device with codesigning disabled. You will have to manually codesign before deploying to device.''',
        )
        ..warn(
          '''shorebird preview will not work for releases created with "--no-codesign". However, you can still preview your app by signing the generated .xcarchive in Xcode.''',
        );
    }

    final File exportOptionsPlist;
    try {
      exportOptionsPlist = ios.exportOptionsPlistFromArgs(argResults);
    } catch (error) {
      logger.err('$error');
      exit(ExitCode.usage.code);
    }

    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress =
        logger.progress('Building ipa with Flutter $flutterVersionString');
    try {
      await artifactBuilder.buildIpa(
        codesign: codesign,
        exportOptionsPlist: exportOptionsPlist,
        flavor: flavor,
        target: target,
      );
      buildProgress.complete();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      exit(ExitCode.software.code);
    }

    final xcarchiveDirectory = artifactManager.getXcarchiveDirectory();
    if (xcarchiveDirectory == null) {
      logger.err('Unable to find .xcarchive directory');
      exit(ExitCode.software.code);
    }

    final appDirectory = artifactManager.getIosAppDirectory(
      xcarchiveDirectory: xcarchiveDirectory,
    );

    if (appDirectory == null) {
      logger.err('Unable to find .app directory');
      exit(ExitCode.software.code);
    }

    return xcarchiveDirectory;
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final plistFile = File(p.join(releaseArtifactRoot.path, 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}');
      exit(ExitCode.software.code);
    }

    try {
      return Plist(file: plistFile).versionNumber;
    } catch (error) {
      logger.err(
        '''Failed to determine release version from ${plistFile.path}: $error''',
      );
      exit(ExitCode.software.code);
    }
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final xcarchiveDirectory = artifactManager.getXcarchiveDirectory()!;
    await codePushClientWrapper.createIosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      xcarchivePath: xcarchiveDirectory.path,
      runnerPath: artifactManager
          .getIosAppDirectory(xcarchiveDirectory: xcarchiveDirectory)!
          .path,
      isCodesigned: codesign,
    );
  }

  @override
  String get postReleaseInstructions {
    final relativeArchivePath = p.relative(
      artifactManager.getXcarchiveDirectory()!.path,
    );
    if (codesign) {
      final ipa = artifactManager.getIpa();
      if (ipa == null) {
        logger.err('Could not find ipa file');
        exit(ExitCode.software.code);
      }

      final relativeIpaPath = p.relative(ipa.path);
      return '''

Your next step is to upload your app to App Store Connect.

To upload to the App Store, do one of the following:
    1. Open ${lightCyan.wrap(relativeArchivePath)} in Xcode and use the "Distribute App" flow.
    2. Drag and drop the ${lightCyan.wrap(relativeIpaPath)} bundle into the Apple Transporter macOS app (https://apps.apple.com/us/app/transporter/id1450874784).
    3. Run ${lightCyan.wrap('xcrun altool --upload-app --type ios -f $relativeIpaPath --apiKey your_api_key --apiIssuer your_issuer_id')}.
       See "man altool" for details about how to authenticate with the App Store Connect API key.
''';
    } else {
      return '''

Your next step is to submit the archive at ${lightCyan.wrap(relativeArchivePath)} to the App Store using Xcode.

You can open the archive in Xcode by running:
    ${lightCyan.wrap('open $relativeArchivePath')}

${styleBold.wrap('Make sure to uncheck "Manage Version and Build Number", or else shorebird will not work.')}
''';
    }
  }

  @override
  Future<UpdateReleaseMetadata> releaseMetadata() async =>
      UpdateReleaseMetadata(
        releasePlatform: releaseType.releasePlatform,
        flutterVersionOverride: argResults['flutter-version'] as String?,
        generatedApks: false,
        environment: BuildEnvironmentMetadata(
          operatingSystem: platform.operatingSystem,
          operatingSystemVersion: platform.operatingSystemVersion,
          shorebirdVersion: packageVersion,
          xcodeVersion: await xcodeBuild.version(),
        ),
      );
}
