import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/metadata/update_release_metadata.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template macos_releaser}
/// Functions to build and publish a macOS release.
/// {@endtemplate}
class MacosReleaser extends Releaser {
  /// {@macro macos_releaser}
  MacosReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  /// The Developer ID Installer identity to sign the PKG with, if provided.
  String? get pkgSign => argResults['pkg-sign'] as String?;

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  @override
  String get artifactDisplayName => 'macOS app';

  @override
  Future<void> assertArgsAreValid() async {
    if (argResults.wasParsed('release-version')) {
      logger.err(
        '''
The "--release-version" flag is only supported for aar and ios-framework releases.
        
To change the version of this release, change your app's version in your pubspec.yaml.''',
      );
      throw ProcessExit(ExitCode.usage.code);
    }

    if (argResults.rest.contains('--obfuscate')) {
      // Obfuscated releases break patching, so we don't support them.
      // See https://github.com/shorebirdtech/shorebird/issues/1619
      logger
        ..err('Shorebird does not currently support obfuscation on macOS.')
        ..info(
          '''We hope to support obfuscation in the future. We are tracking this work at ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1619'))}.''',
        );
      throw ProcessExit(ExitCode.unavailable.code);
    }
  }

  @override
  Version? get minimumFlutterVersion => minimumSupportedMacosFlutterVersion;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.macosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (e) {
      throw ProcessExit(e.exitCode.code);
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

    final base64PublicKey = await getEncodedPublicKey();
    await artifactBuilder.buildMacos(
      codesign: codesign,
      flavor: flavor,
      target: target,
      args: argResults.forwardedArgs,
      base64PublicKey: base64PublicKey,
    );

    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    // If PKG signing is requested, create a PKG installer as an additional
    // artifact
    if (pkgSign != null) {
      await _createPkgInstaller(appDirectory);
    }

    // Always return the app directory for other processes to continue with
    return appDirectory;
  }

  /// Creates a signed PKG installer from the built app.
  Future<File> _createPkgInstaller(Directory appDirectory) async {
    final buildDir = Directory(
      p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
        'macos',
        'pkg',
      ),
    );

    if (!buildDir.existsSync()) {
      buildDir.createSync(recursive: true);
    }

    final appName = p.basenameWithoutExtension(appDirectory.path);
    final pkgPath = p.join(buildDir.path, '$appName.pkg');

    // Create signed PKG installer directly with productbuild
    final buildProgress = logger.progress('Creating signed PKG installer');
    final productBuildResult = await productBuild.buildFromComponent(
      componentPath: appDirectory.path,
      installLocation: '/Applications',
      outputPath: pkgPath,
      sign: pkgSign,
    );

    if (productBuildResult.exitCode != 0) {
      buildProgress.fail('Failed to create signed PKG installer');
      logger.err('productbuild error: ${productBuildResult.stderr}');
      throw ProcessExit(ExitCode.software.code);
    }
    buildProgress.complete();

    logger.info('Created signed PKG installer at $pkgPath');
    return File(pkgPath);
  }

  @override
  Future<String> getReleaseVersion({
    required FileSystemEntity releaseArtifactRoot,
  }) async {
    final plistFile = File(
      p.join(releaseArtifactRoot.path, 'Contents', 'Info.plist'),
    );
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}');
      throw ProcessExit(ExitCode.software.code);
    }

    try {
      return Plist(file: plistFile).versionNumber;
    } on Exception catch (error) {
      logger.err(
        '''Failed to determine release version from ${plistFile.path}: $error''',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final String? podfileLockHash;
    if (shorebirdEnv.macosPodfileLockFile.existsSync()) {
      podfileLockHash = sha256
          .convert(shorebirdEnv.macosPodfileLockFile.readAsBytesSync())
          .toString();
    } else {
      podfileLockHash = null;
    }

    await codePushClientWrapper.createMacosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appPath: appDirectory.path,
      isCodesigned: codesign,
      podfileLockHash: podfileLockHash,
    );
  }

  @override
  Future<UpdateReleaseMetadata> updatedReleaseMetadata(
    UpdateReleaseMetadata metadata,
  ) async => metadata.copyWith(
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );

  @override
  String get postReleaseInstructions {
    final appPath = artifactManager.getMacOSAppDirectory(flavor: flavor)!.path;

    if (pkgSign != null) {
      final buildDir = p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
        'macos',
        'pkg',
      );
      return '''

macOS app created at $appPath.
macOS PKG installer created at $buildDir.
The PKG file is signed and ready for distribution.
''';
    }

    return '''

macOS app created at $appPath.
''';
  }
}
