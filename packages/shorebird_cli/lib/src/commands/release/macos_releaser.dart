import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/release/release.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/detail_progress.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template macos_releaser}
/// Functions to build and publish a macOS release.
/// {@endtemplate}
class MacOSReleaser extends Releaser {
  /// {@macro macos_releaser}
  MacOSReleaser({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  @override
  Future<void> assertArgsAreValid() async {
    // TODO: implement assertArgsAreValid
  }

  @override
  Future<void> assertPreconditions() async {
    // TODO: implement assertPreconditions
    // TODO: ensure app has network capabilities
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

    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress = logger.detailProgress(
      'Building app bundle with Flutter $flutterVersionString',
    );

    try {
      await artifactBuilder.buildMacos(
        codesign: codesign,
        flavor: flavor,
        target: target,
        args: argResults.forwardedArgs,
        base64PublicKey: argResults.encodedPublicKey,
        buildProgress: buildProgress,
      );
      buildProgress.complete();
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      throw ProcessExit(ExitCode.software.code);
    }

    final appDirectory = artifactManager.getMacOSAppDirectory();
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
    } catch (error) {
      logger.err(
        '''Failed to determine release version from ${plistFile.path}: $error''',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }

  // TODO
  @override
  String get postReleaseInstructions => 'TODO';

  @override
  Future<void> uploadReleaseArtifacts({
    required Release release,
    required String appId,
  }) async {
    print("in uploadReleaseArtifacts");
    final xcarchiveDirectory = artifactManager.getMacOSAppDirectory();
    if (xcarchiveDirectory == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }
    // final String? podfileLockHash;
    // if (shorebirdEnv.podfileLockFile.existsSync()) {
    //   podfileLockHash = sha256
    //       .convert(shorebirdEnv.podfileLockFile.readAsBytesSync())
    //       .toString();
    // } else {
    //   podfileLockHash = null;
    // }
    await codePushClientWrapper.createMacosReleaseArtifacts(
      appId: appId,
      releaseId: release.id,
      appPath: xcarchiveDirectory.path,
      // runnerPath: artifactManager
      //     .getIosAppDirectory(xcarchiveDirectory: xcarchiveDirectory)!
      //     .path,
      isCodesigned: codesign,
      // podfileLockHash: podfileLockHash,
    );
  }
}
