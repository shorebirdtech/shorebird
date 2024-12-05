import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/detail_progress.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

// TODO: consolidate this - this was copied from [IosPatcher]
typedef _LinkResult = ({int exitCode, double? linkPercentage});

/// {@template macos_patcher}
/// Functions to create and apply patches to a macOS release.
/// {@endtemplate}
class MacosPatcher extends Patcher {
  /// {@macro macos_patcher}
  MacosPatcher({
    required super.argParser,
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  String get _aotOutputPath => p.join(buildDirectory.path, 'out.aot');

  String get _appDillCopyPath => p.join(buildDirectory.path, 'app.dill');

  String get _vmcodeOutputPath => p.join(buildDirectory.path, 'out.vmcode');

  @visibleForTesting
  double? lastBuildLinkPercentage;

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  @override
  String get primaryReleaseArtifactArch => 'app';

  @override
  Future<void> assertPreconditions() async {
    // TODO: implement assertPreconditions
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    // return DiffStatus({
    //   hasAssetChanges: false,
    //   hasNativeChanges: false,
    // });
    // TODO: implement assertUnpatchableDiffs
    // throw UnimplementedError();
    // TODO
    return DiffStatus(hasAssetChanges: false, hasNativeChanges: false);
  }

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    try {
      final shouldCodesign = argResults['codesign'] == true;
      final (flutterVersionAndRevision, flutterVersion) = await (
        shorebirdFlutter.getVersionAndRevision(),
        shorebirdFlutter.getVersion(),
      ).wait;

      if ((flutterVersion ?? minimumSupportedMacosFlutterVersion) <
          minimumSupportedIosFlutterVersion) {
        logger.err(
          '''
macos patches are not supported with Flutter versions older than $minimumSupportedIosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''',
        );
        throw ProcessExit(ExitCode.software.code);
      }

      final buildProgress = logger.detailProgress(
        'Building patch with Flutter $flutterVersionAndRevision',
      );
      final IpaBuildResult ipaBuildResult;
      try {
        // If buildIpa is called with a different codesign value than the
        // release was, we will erroneously report native diffs.
        ipaBuildResult = await artifactBuilder.buildMacos(
          codesign: shouldCodesign,
          flavor: flavor,
          target: target,
          args: argResults.forwardedArgs +
              buildNameAndNumberArgsFromReleaseVersion(releaseVersion),
          base64PublicKey: argResults.encodedPublicKey,
          buildProgress: buildProgress,
        );
      } on ProcessException catch (error) {
        buildProgress.fail('Failed to build: ${error.message}');
        rethrow;
      } on ArtifactBuildException catch (error) {
        buildProgress.fail('Failed to build macos app');
        logger.err(error.message);
        rethrow;
      }

      try {
        if (splitDebugInfoPath != null) {
          Directory(splitDebugInfoPath!).createSync(recursive: true);
        }
        await artifactBuilder.buildElfAotSnapshot(
          appDillPath: ipaBuildResult.kernelFile.path,
          outFilePath: _aotOutputPath,
          // TODO
          // additionalArgs: splitDebugInfoArgs(splitDebugInfoPath),
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

    final appPath = artifactManager.getMacOSAppDirectory()!.path;
    final tempDir = await Directory.systemTemp.createTemp();
    final zippedApp = File(p.join(tempDir.path, '${p.basename(appPath)}.zip'));
    // FIXME: using ditto here because zipToTempFile is not properly capturing
    // the app folder structure (the top folder after zipping is Content,
    // instead of the MyApp.app directory).
    // package:archive also seems to be having some trouble unzipping .app files
    //
    // final zippedApp = await Directory(appPath).zipToTempFile();
    await Process.run('ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      '--keepParent',
      appPath,
      zippedApp.path,
    ]);
    print('appPath is $appPath');
    return zippedApp;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  }) async {
    // Verify that we have built a patch .app
    if (artifactManager.getMacOSAppDirectory()?.path == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final unzipProgress = logger.progress('Extracting release artifact');
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: releaseArtifact,
      outputDirectory: tempDir,
    );
    final releaseAppPath = tempDir.path;

    unzipProgress.complete();
    print('release app path is $releaseAppPath');
    final appDirectory = artifactManager.getMacosAppDirectory(
      parentDirectory: Directory(releaseAppPath),
    );
    if (appDirectory == null) {
      logger.err('Unable to find release artifact .app directory');
      throw ProcessExit(ExitCode.software.code);
    }
    final releaseArtifactFile = File(
      p.join(
        appDirectory.path,
        'Contents',
        'Frameworks',
        'App.framework',
        'App',
      ),
    );
    print('release artifact file is $releaseArtifactFile');

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

    // TODO: support x86_64
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
    final appPath = artifactManager.getMacOSAppDirectory()?.path;
    if (appPath == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final plistFile = File(p.join(appPath, 'Contents', 'Info.plist'));
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
        // TODO
        // additionalArgs: splitDebugInfoArgs(splitDebugInfoPath),
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
