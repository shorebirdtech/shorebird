import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/apple_patcher_mixin.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// {@template ios_patcher}
/// Functions to create an iOS patch.
/// {@endtemplate}
class IosPatcher extends Patcher
    with
        ApplePatcherMixin,
        ApplePodfileLockPatcherMixin,
        AppleLinkerPatcherMixin {
  /// {@macro ios_patcher}
  IosPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  String get primaryReleaseArtifactArch => 'xcarchive';

  @override
  String? get supplementaryReleaseArtifactArch => 'ios_supplement';

  @override
  List<Validator> get applePlatformValidators => doctor.iosCommandValidators;

  @override
  String? get localPodfileLockHash => shorebirdEnv.iosPodfileLockHash;

  @override
  String get podfileLockRelativePath => 'ios/Podfile.lock';

  @override
  Future<void> assertArgsAreValid() async {
    final exportOptionsPlistFile = argResults.file(
      CommonArguments.exportOptionsPlistArg.name,
    );
    if (exportOptionsPlistFile != null) {
      try {
        assertValidExportOptionsPlist(exportOptionsPlistFile);
      } on InvalidExportOptionsPlistException catch (error) {
        logger.err(error.message);
        throw ProcessExit(ExitCode.usage.code);
      }
    }
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final shouldCodesign = argResults['codesign'] == true;
    final (flutterVersionAndRevision, flutterVersion) = await (
      shorebirdFlutter.getVersionAndRevision(),
      shorebirdFlutter.getVersion(),
    ).wait;

    if ((flutterVersion ?? minimumSupportedIosFlutterVersion) <
        minimumSupportedIosFlutterVersion) {
      logger.err('''
This release was built with Flutter $flutterVersionAndRevision, but iOS patches need Flutter $minimumSupportedIosFlutterVersion or newer.
A release cannot change Flutter versions, so create a new release with ${lightCyan.wrap('shorebird release ios --flutter-version=<version>')} and patch that one.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''');
      throw ProcessExit(ExitCode.software.code);
    }

    final buildArgs = [
      ...argResults.forwardedArgs,
      ...extraBuildArgs,
      ...buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
    ];

    // If buildIpa is called with a different codesign value than the
    // release was, we will erroneously report native diffs.
    final ipaBuildResult = await artifactBuilder.buildIpa(
      codesign: shouldCodesign,
      flavor: flavor,
      target: target,
      args: buildArgs,
      base64PublicKey: argResults.encodedPublicKey,
    );

    await buildAppleElfAotSnapshot(
      appDillPath: ipaBuildResult.kernelFile.path,
      outFilePath: aotOutputPath,
      genSnapshotArtifact: ShorebirdArtifact.genSnapshotIos,
    );

    // Copy the kernel file to the build directory so that it can be used
    // to generate a patch.
    ipaBuildResult.kernelFile.copySync(appDillCopyPath);

    return artifactManager.getXcarchiveDirectory()!.zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    Directory? supplementDirectory,
  }) async {
    // Verify that we have built a patch .xcarchive
    if (artifactManager.getXcarchiveDirectory()?.path == null) {
      _noXcarchiveFound();
    }

    final unzipProgress = logger.progress('Extracting release artifact');

    late final String releaseXcarchivePath;
    {
      final tempDir = Directory.systemTemp.createTempSync();
      await artifactManager.extractZip(
        zipFile: releaseArtifact,
        outputDirectory: tempDir,
      );
      releaseXcarchivePath = tempDir.path;
    }

    final releaseSupplementDir =
        supplementDirectory ?? Directory.systemTemp.createTempSync();

    unzipProgress.complete();
    final appDirectory = artifactManager.getIosAppDirectory(
      xcarchiveDirectory: Directory(releaseXcarchivePath),
    );
    if (appDirectory == null) {
      logger
        ..err(
          'The release .xcarchive downloaded from Shorebird has no '
          'Products/Applications/*.app directory.',
        )
        ..info(
          'Re-run to download it again. If this persists, the release '
          'artifact is damaged; create a new release with '
          '${lightCyan.wrap('shorebird release ios')} and patch that one.',
        );
      throw ProcessExit(ExitCode.software.code);
    }
    final releaseArtifactFile = File(
      p.join(appDirectory.path, 'Frameworks', 'App.framework', 'App'),
    );

    return linkAndBundlePatch(
      releaseArtifactFile: releaseArtifactFile,
      releaseSupplementDir: releaseSupplementDir,
      podfileLockHash: shorebirdEnv.iosPodfileLockHash,
    );
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final archivePath = artifactManager.getXcarchiveDirectory()?.path;
    if (archivePath == null) _noXcarchiveFound();

    final plistFile = File(p.join(archivePath, 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger
        ..err('No Info.plist file found at ${plistFile.path}.')
        ..info(_passReleaseVersionHint);
      throw ProcessExit(ExitCode.software.code);
    }

    final plist = Plist(file: plistFile);
    try {
      return plist.versionNumber;
    } on Exception catch (error) {
      logger
        ..err(
          'Failed to determine release version from ${plistFile.path}: $error',
        )
        ..info(_passReleaseVersionHint);
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// The release version is only read from the archive when the user did not
  /// pass one, so passing one is always a way around a broken read.
  static const _passReleaseVersionHint =
      'Pass --release-version=<version> (or --release-version=latest) to '
      'skip reading the version from the archive.';

  /// Logs that `flutter build ipa` left no .xcarchive where Shorebird looks
  /// for it and throws [ProcessExit].
  Never _noXcarchiveFound() {
    final archiveDirectory = p.join(
      shorebirdEnv.getShorebirdProjectRoot()!.path,
      'build',
      'ios',
      'archive',
    );
    logger
      ..err('No .xcarchive found in $archiveDirectory after the build.')
      ..info(
        'Shorebird looks for the archive that '
        '${lightCyan.wrap('flutter build ipa')} writes there. '
        'Re-run with --verbose to see the build output.',
      );
    throw ProcessExit(ExitCode.software.code);
  }
}
