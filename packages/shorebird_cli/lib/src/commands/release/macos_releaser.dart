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
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
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

  /// Whether the user is building with obfuscation.
  bool get _useObfuscation =>
      argResults.forwardedArgs.contains('--obfuscate');

  /// The path where the obfuscation map will be saved during the build.
  String get _obfuscationMapPath => p.join(
        projectRoot.path,
        'build',
        'shorebird',
        'obfuscation_map.json',
      );

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

    final buildArgs = [...argResults.forwardedArgs];
    if (_useObfuscation) {
      final mapDir = Directory(p.dirname(_obfuscationMapPath));
      if (!mapDir.existsSync()) {
        mapDir.createSync(recursive: true);
      }
      buildArgs.add(
        '--extra-gen-snapshot-options='
        '--save-obfuscation-map=$_obfuscationMapPath',
      );
    }

    await artifactBuilder.buildMacos(
      codesign: codesign,
      flavor: flavor,
      target: target,
      args: buildArgs,
      base64PublicKey: base64PublicKey,
    );

    if (_useObfuscation) {
      final mapFile = File(_obfuscationMapPath);
      if (!mapFile.existsSync()) {
        logger.err('Obfuscation was enabled but the obfuscation map was not '
            'generated at $_obfuscationMapPath');
        throw ProcessExit(ExitCode.software.code);
      }
      logger.detail('Obfuscation map saved to $_obfuscationMapPath');
    }

    final appDirectory = artifactManager.getMacOSAppDirectory(flavor: flavor);
    if (appDirectory == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    return appDirectory;
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

    final obfuscationMapFile = File(_obfuscationMapPath);
    await codePushClientWrapper.createMacosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appPath: appDirectory.path,
      isCodesigned: codesign,
      podfileLockHash: podfileLockHash,
      obfuscationMapPath:
          obfuscationMapFile.existsSync() ? _obfuscationMapPath : null,
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
  String get postReleaseInstructions =>
      '''

macOS app created at ${artifactManager.getMacOSAppDirectory(flavor: flavor)!.path}.
''';
}
