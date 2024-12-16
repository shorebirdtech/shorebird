import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/plist.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/code_signer.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/detail_progress.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

// TODO(bryanoltman): consolidate this - this was copied from [IosPatcher]
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

  String get _patchClassTableLinkInfoPath =>
      p.join(buildDirectory.path, 'macos', 'shorebird', 'App.ct.link');

  String get _patchClassTableLinkDebugInfoPath =>
      p.join(buildDirectory.path, 'macos', 'shorebird', 'App.class_table.json');

  String get _aotOutputPath => p.join(buildDirectory.path, 'out.aot');

  String get _appDillCopyPath => p.join(buildDirectory.path, 'app.dill');

  String get _vmcodeOutputPath => p.join(buildDirectory.path, 'out.vmcode');

  /// The name of the split debug info file when the target is macOS.
  // FIXME: this is only the arm symbols, x64 symbols are at
  // app.darwin-x86_64.symbols
  static const splitDebugInfoFileName = 'app.darwin-arm64.symbols';

  /// The additional gen_snapshot arguments to use when building the patch with
  /// `--split-debug-info`.
  static List<String> splitDebugInfoArgs(String? splitDebugInfoPath) {
    return splitDebugInfoPath != null
        ? [
            '--dwarf-stack-traces',
            '--resolve-dwarf-paths',
            '''--save-debugging-info=${p.join(p.absolute(splitDebugInfoPath), splitDebugInfoFileName)}''',
          ]
        : <String>[];
  }

  @override
  String? get supplementaryReleaseArtifactArch => 'macos_supplement';

  /// The link percentage from the most recent patch build.
  @visibleForTesting
  double? lastBuildLinkPercentage;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  @override
  ReleaseType get releaseType => ReleaseType.macos;

  /// Whether to codesign the release.
  bool get codesign => argResults['codesign'] == true;

  @override
  String get primaryReleaseArtifactArch => 'app';

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkShorebirdInitialized: true,
        checkUserIsAuthenticated: true,
        validators: doctor.macosCommandValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (error) {
      throw ProcessExit(error.exitCode.code);
    }
  }

  // FIXME: this is a direct copy of IosPatcher's implementation. We should
  // consolidate this and other copied code.
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
      archiveDiffer: const AppleArchiveDiffer(),
      allowAssetChanges: allowAssetDiffs,
      allowNativeChanges: allowNativeDiffs,
      confirmNativeChanges: false,
    );

    if (!diffStatus.hasNativeChanges) {
      return diffStatus;
    }

    final String? podfileLockHash;
    if (shorebirdEnv.macosPodfileLockFile.existsSync()) {
      podfileLockHash = sha256
          .convert(shorebirdEnv.macosPodfileLockFile.readAsBytesSync())
          .toString();
    } else {
      podfileLockHash = null;
    }

    if (releaseArtifact.podfileLockHash != null &&
        podfileLockHash != releaseArtifact.podfileLockHash) {
      logger.warn(
        '''
Your macos/Podfile.lock is different from the one used to build the release.
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
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    try {
      final (flutterVersionAndRevision, flutterVersion) = await (
        shorebirdFlutter.getVersionAndRevision(),
        shorebirdFlutter.getVersion(),
      ).wait;

      if ((flutterVersion ?? minimumSupportedMacosFlutterVersion) <
          minimumSupportedMacosFlutterVersion) {
        logger.err(
          '''
macOS patches are not supported with Flutter versions older than $minimumSupportedMacosFlutterVersion.
For more information see: ${supportedFlutterVersionsUrl.toLink()}''',
        );
        throw ProcessExit(ExitCode.software.code);
      }

      final buildProgress = logger.detailProgress(
        'Building patch with Flutter $flutterVersionAndRevision',
      );
      final MacosBuildResult macosBuildResult;
      try {
        // If buildMacos is called with a different codesign value than the
        // release was, we will erroneously report native diffs.
        macosBuildResult = await artifactBuilder.buildMacos(
          codesign: codesign,
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
        buildProgress.fail('Failed to build macOS app');
        logger.err(error.message);
        rethrow;
      }

      try {
        if (splitDebugInfoPath != null) {
          Directory(splitDebugInfoPath!).createSync(recursive: true);
        }
        await artifactBuilder.buildElfAotSnapshot(
          appDillPath: macosBuildResult.kernelFile.path,
          outFilePath: _aotOutputPath,
          genSnapshotArtifact: ShorebirdArtifact.genSnapshotMacOS,
          additionalArgs: splitDebugInfoArgs(splitDebugInfoPath),
        );
      } catch (error) {
        buildProgress.fail('$error');
        rethrow;
      }

      // Copy the kernel file to the build directory so that it can be used
      // to generate a patch.
      macosBuildResult.kernelFile.copySync(_appDillCopyPath);

      buildProgress.complete();
    } catch (_) {
      throw ProcessExit(ExitCode.software.code);
    }

    final appPath = artifactManager.getMacOSAppDirectory()!.path;
    final tempDir = await Directory.systemTemp.createTemp();
    final zippedApp = File(p.join(tempDir.path, '${p.basename(appPath)}.zip'));
    await ditto.archive(
      source: appPath,
      destination: zippedApp.path,
      // keepParent is false here in order to ensure the directory structure of
      // this zip file matches what will be provided to the [AppleArchiveDiffer]
      // (which uses package:archive to stream zip file contents).
    );
    return zippedApp;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
    File? supplementArtifact,
  }) async {
    if (supplementArtifact == null) {
      logger.err('Unable to find supplement directory');
      throw ProcessExit(ExitCode.software.code);
    }

    // Verify that we have built a patch .app
    if (artifactManager.getMacOSAppDirectory()?.path == null) {
      logger.err('Unable to find .app directory');
      throw ProcessExit(ExitCode.software.code);
    }

    final unzipProgress = logger.progress('Extracting release artifact');
    final releaseAppDirectory = Directory.systemTemp.createTempSync();
    await ditto.extract(
      source: releaseArtifact.path,
      destination: releaseAppDirectory.path,
    );

    File? releaseClassTableLinkInfoFile;
    File? releaseClassTableLinkDebugInfoFile;
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: supplementArtifact,
      outputDirectory: tempDir,
    );
    releaseClassTableLinkInfoFile = File(p.join(tempDir.path, 'App.ct.link'));
    if (!releaseClassTableLinkInfoFile.existsSync()) {
      logger.err('Unable to find class table link info file');
      throw ProcessExit(ExitCode.software.code);
    }

    releaseClassTableLinkDebugInfoFile = File(
      p.join(tempDir.path, 'App.class_table.json'),
    );
    if (!releaseClassTableLinkDebugInfoFile.existsSync()) {
      logger.err('Unable to find class table link debug info file');
      throw ProcessExit(ExitCode.software.code);
    }

    unzipProgress.complete();
    final releaseArtifactFile = File(
      p.join(
        releaseAppDirectory.path,
        'Contents',
        'Frameworks',
        'App.framework',
        'App',
      ),
    );

    // Copy the release's class table link info file next to the release
    // snapshot so that it can be used to generate a patch.
    releaseClassTableLinkInfoFile.copySync(
      p.join(releaseArtifactFile.parent.path, 'App.ct.link'),
    );
    releaseClassTableLinkDebugInfoFile.copySync(
      p.join(releaseArtifactFile.parent.path, 'App.class_table.json'),
    );

    // Copy the patch's class table link info file to the build directory
    // so that it can be used to generate a patch.
    File(_patchClassTableLinkInfoPath).copySync(
      p.join(buildDirectory.path, 'out.ct.link'),
    );
    File(_patchClassTableLinkDebugInfoPath).copySync(
      p.join(buildDirectory.path, 'out.class_table.json'),
    );

    final (:exitCode, :linkPercentage) = await _runLinker(
      releaseArtifact: releaseArtifactFile,
      kernelFile: File(_appDillCopyPath),
    );
    if (exitCode != ExitCode.success.code) throw ProcessExit(exitCode);
    if (linkPercentage != null && linkPercentage < Patcher.minLinkPercentage) {
      logger.warn(Patcher.lowLinkPercentageWarning(linkPercentage));
    }
    lastBuildLinkPercentage = linkPercentage;

    final patchBuildFile = File(_vmcodeOutputPath);

    final patchBaseProgress = logger.progress('Generating patch diff base');
    final analyzeSnapshotPath = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.analyzeSnapshotMacOS,
    );

    final File patchBaseFile;
    try {
      // Generate a stable diff base and use that to create a patch.
      patchBaseFile = await aotTools.generatePatchDiffBase(
        analyzeSnapshotPath: analyzeSnapshotPath,
        releaseSnapshot: releaseArtifactFile,
      );
      patchBaseProgress.complete();
    } catch (error) {
      patchBaseProgress.fail('$error');
      throw ProcessExit(ExitCode.software.code);
    }

    final patchFile = File(
      await artifactManager.createDiff(
        releaseArtifactPath: patchBaseFile.path,
        patchArtifactPath: patchBuildFile.path,
      ),
    );

    final patchFileSize = patchFile.statSync().size;
    final privateKeyFile = argResults.file(CommonArguments.privateKeyArg.name);
    final hash = sha256.convert(patchBuildFile.readAsBytesSync()).toString();
    final hashSignature = privateKeyFile != null
        ? codeSigner.sign(
            message: hash,
            privateKeyPemFile: privateKeyFile,
          )
        : null;

    // TODO(bryanoltman): support x86_64
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

  @override
  Future<CreatePatchMetadata> updatedCreatePatchMetadata(
    CreatePatchMetadata metadata,
  ) async =>
      metadata.copyWith(
        linkPercentage: lastBuildLinkPercentage,
        environment: metadata.environment.copyWith(
          xcodeVersion: await xcodeBuild.version(),
        ),
      );

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
        artifact: ShorebirdArtifact.analyzeSnapshotMacOS,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshotMacOS,
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
        additionalArgs: splitDebugInfoArgs(splitDebugInfoPath),
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
