// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patcher.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

typedef _LinkResult = ({int exitCode, double? linkPercentage});

/// {@template ios_patcher}
/// Functions to create an iOS patch.
/// {@endtemplate}
class IosPatcher extends Patcher {
  /// {@macro ios_patcher}
  IosPatcher({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  String get _aotOutputPath => p.join(buildDirectory.path, 'out.aot');

  String get _vmcodeOutputPath => p.join(buildDirectory.path, 'out.vmcode');

  String get _appDillCopyPath => p.join(buildDirectory.path, 'app.dill');

  @visibleForTesting
  double? lastBuildLinkPercentage;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  String get primaryReleaseArtifactArch => 'xcarchive';

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkShorebirdInitialized: true,
        checkUserIsAuthenticated: true,
        validators: doctor.iosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (error) {
      throw ProcessExit(error.exitCode.code);
    }
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    // Check for diffs without warning about native changes, as Xcode builds
    // can be nondeterministic. So we still have some hope of alerting users of
    // unpatchable native changes, we compare the Podfile.lock hash between the
    // patch and the release.
    final diffStatus =
        await patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
      localArchive: patchArchive,
      releaseArchive: releaseArchive,
      archiveDiffer: const IosArchiveDiffer(),
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
      confirmNativeChanges: false,
    );

    if (!diffStatus.hasNativeChanges) {
      return diffStatus;
    }

    final String? podfileLockHash;
    if (shorebirdEnv.podfileLockFile.existsSync()) {
      podfileLockHash = sha256
          .convert(shorebirdEnv.podfileLockFile.readAsBytesSync())
          .toString();
    } else {
      podfileLockHash = null;
    }

    if (releaseArtifact.podfileLockHash != null &&
        podfileLockHash != releaseArtifact.podfileLockHash) {
      logger.warn(
        '''
Your ios/Podfile.lock is different from the one used to build the release.
This may indicate that the patch contains native changes, which cannot be applied with a patch. Proceeding may result in unexpected behavior or crashes.''',
      );

      if (!allowNativeDiffs) {
        if (!shorebirdEnv.canAcceptUserInput) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          throw UserCancelledException();
        }
      }
    }

    return diffStatus;
  }

  @override
  Future<File> buildPatchArtifact() async {
    final File exportOptionsPlist;
    try {
      exportOptionsPlist = ios.exportOptionsPlistFromArgs(argResults);
    } catch (error) {
      logger.err('$error');
      throw ProcessExit(ExitCode.usage.code);
    }

    try {
      final shouldCodesign = argResults['codesign'] == true;
      final (flutterVersionAndRevision, flutterVersion) = await (
        shorebirdFlutter.getVersionAndRevision(),
        shorebirdFlutter.getVersion(),
      ).wait;

      if ((flutterVersion ?? minimumSupportedIosFlutterVersion) <
          minimumSupportedIosFlutterVersion) {
        logger.err(
          '''
iOS patches are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.
For more information see: $supportedVersionsLink''',
        );
        throw ProcessExit(ExitCode.software.code);
      }

      final buildProgress = logger.progress(
        'Building patch with Flutter $flutterVersionAndRevision',
      );
      final IpaBuildResult ipaBuildResult;
      try {
        // If buildIpa is called with a different codesign value than the
        // release was, we will erroneously report native diffs.
        ipaBuildResult = await artifactBuilder.buildIpa(
          codesign: shouldCodesign,
          exportOptionsPlist: exportOptionsPlist,
          flavor: flavor,
          target: target,
          args: argResults.forwardedArgs +
              buildNameAndNumberArgsFromReleaseVersionArg(),
          base64PublicKey: argResults.encodedPublicKey,
        );
      } on ProcessException catch (error) {
        buildProgress.fail('Failed to build: ${error.message}');
        rethrow;
      } on ArtifactBuildException catch (error) {
        buildProgress.fail('Failed to build IPA');
        logger.err(error.message);
        rethrow;
      }

      try {
        await artifactBuilder.buildElfAotSnapshot(
          appDillPath: ipaBuildResult.kernelFile.path,
          outFilePath: _aotOutputPath,
        );
      } catch (error) {
        buildProgress.fail('$error');
        rethrow;
      }

      // Copy the kernel file to the build directory so that it can be used
      // to generate a patch.
      ipaBuildResult.kernelFile.copySync(_appDillCopyPath);

      buildProgress.complete();
    } catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    return artifactManager.getXcarchiveDirectory()!.zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  }) async {
    // Verify that we have built a patch .xcarchive
    if (artifactManager.getXcarchiveDirectory()?.path == null) {
      logger.err('Unable to find .xcarchive directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final unzipProgress = logger.progress('Extracting release artifact');
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: releaseArtifact,
      outputDirectory: tempDir,
    );
    final releaseXcarchivePath = tempDir.path;

    unzipProgress.complete();
    final appDirectory = artifactManager.getIosAppDirectory(
      xcarchiveDirectory: Directory(releaseXcarchivePath),
    );
    if (appDirectory == null) {
      logger.err('Unable to find release artifact .app directory');
      throw ProcessExit(ExitCode.software.code);
    }
    final releaseArtifactFile = File(
      p.join(
        appDirectory.path,
        'Frameworks',
        'App.framework',
        'App',
      ),
    );

    final useLinker = AotTools.usesLinker(shorebirdEnv.flutterRevision);
    if (useLinker) {
      final (:exitCode, :linkPercentage) = await _runLinker(
        releaseArtifact: releaseArtifactFile,
        kernelFile: File(_appDillCopyPath),
      );
      if (exitCode != ExitCode.success.code) throw ProcessExit(exitCode);
      if (linkPercentage != null &&
          linkPercentage < Patcher.minLinkPercentage) {
        logger.warn(Patcher.lowLinkPercentageWarning(linkPercentage));
      }
      lastBuildLinkPercentage = linkPercentage;
    }

    final patchBuildFile = File(useLinker ? _vmcodeOutputPath : _aotOutputPath);

    final File patchFile;
    if (useLinker && await aotTools.isGeneratePatchDiffBaseSupported()) {
      final patchBaseProgress = logger.progress('Generating patch diff base');
      final analyzeSnapshotPath = shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      );

      final File patchBaseFile;
      try {
        // If the aot_tools executable supports the dump_blobs command, we
        // can generate a stable diff base and use that to create a patch.
        patchBaseFile = await aotTools.generatePatchDiffBase(
          analyzeSnapshotPath: analyzeSnapshotPath,
          releaseSnapshot: releaseArtifactFile,
        );
        patchBaseProgress.complete();
      } catch (error) {
        patchBaseProgress.fail('$error');
        throw ProcessExit(ExitCode.software.code);
      }

      patchFile = File(
        await artifactManager.createDiff(
          releaseArtifactPath: patchBaseFile.path,
          patchArtifactPath: patchBuildFile.path,
        ),
      );
    } else {
      patchFile = patchBuildFile;
    }

    final patchFileSize = patchFile.statSync().size;
    final privateKeyFile = argResults.file(CommonArguments.privateKeyArg.name);
    final hash = sha256.convert(patchBuildFile.readAsBytesSync()).toString();
    final hashSignature = privateKeyFile != null
        ? codeSigner.sign(
            message: hash,
            privateKeyPemFile: privateKeyFile,
          )
        : null;

    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: patchFile.path,
        hash: hash,
        size: patchFileSize,
        hashSignature: hashSignature,
      ),
    };
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final archivePath = artifactManager.getXcarchiveDirectory()?.path;
    if (archivePath == null) {
      logger.err('Unable to find .xcarchive directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final plistFile = File(p.join(archivePath, 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}.');
      throw ProcessExit(ExitCode.software.code);
    }

    final plist = Plist(file: plistFile);
    try {
      return plist.versionNumber;
    } catch (error) {
      logger.err(
        'Failed to determine release version from ${plistFile.path}: $error',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }

  @override
  Future<CreatePatchMetadata> createPatchMetadata(DiffStatus diffStatus) async {
    return CreatePatchMetadata(
      releasePlatform: releaseType.releasePlatform,
      usedIgnoreAssetChangesFlag: allowAssetDiffs,
      hasAssetChanges: diffStatus.hasAssetChanges,
      usedIgnoreNativeChangesFlag: allowNativeDiffs,
      hasNativeChanges: diffStatus.hasNativeChanges,
      linkPercentage: lastBuildLinkPercentage,
      environment: BuildEnvironmentMetadata(
        operatingSystem: platform.operatingSystem,
        operatingSystemVersion: platform.operatingSystemVersion,
        shorebirdVersion: packageVersion,
        xcodeVersion: await xcodeBuild.version(),
      ),
    );
  }

  Future<_LinkResult> _runLinker({
    required File releaseArtifact,
    required File kernelFile,
  }) async {
    final patch = File(_aotOutputPath);

    if (!patch.existsSync()) {
      logger.err('Unable to find patch AOT file at ${patch.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshot,
    );

    final linkProgress = logger.progress('Linking AOT files');
    double? linkPercentage;
    final dumpDebugInfoDir = await aotTools.isLinkDebugInfoSupported()
        ? Directory.systemTemp.createTempSync()
        : null;

    Future<void> dumpDebugInfo() async {
      if (dumpDebugInfoDir == null) return;

      final debugInfoZip = await dumpDebugInfoDir.zipToTempFile();
      debugInfoZip.copySync(p.join('build', debugInfoFile.path));
      logger.detail('Link debug info saved to ${debugInfoFile.path}');
    }

    try {
      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patch.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        outputPath: _vmcodeOutputPath,
        workingDirectory: buildDirectory.path,
        kernel: kernelFile.path,
        dumpDebugInfoPath: dumpDebugInfoDir?.path,
      );
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    } finally {
      await dumpDebugInfo();
    }
    linkProgress.complete();
    return (exitCode: ExitCode.success.code, linkPercentage: linkPercentage);
  }
}
