import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch_new/patcher.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
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

  // Link percentage that is considered the minimum before a user might notice.
  // Our early testing has shown that about:
  // - 1/3rd of patches link at 99%
  // - 1/3rd of patches link between 20% and 99%
  // - 1/3rd of patches link below 20%
  // Most lowering is likely due to:
  // https://github.com/shorebirdtech/shorebird/issues/1825
  static const double minLinkPercentage = 75;

  static String lowLinkPercentageWarning(double linkPercentage) {
    return '''
${lightCyan.wrap('shorebird patch')} was only able to share ${linkPercentage.toStringAsFixed(1)}% of Dart code with the released app.
This means the patched code may execute slower than expected.
https://docs.shorebird.dev/status#link-percentage-ios
''';
  }

  double? _linkPercentage;

  @override
  ReleaseType get releaseType => ReleaseType.ios;

  @override
  String get primaryReleaseArtifactArch => 'ipa';

  @override
  ArchiveDiffer get archiveDiffer => IosArchiveDiffer();

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
      exit(error.exitCode.code);
    }
  }

  @override
  Future<File> buildPatchArtifact() async {
    final File exportOptionsPlist;
    try {
      exportOptionsPlist = ios.exportOptionsPlistFromArgs(argResults);
    } catch (error) {
      logger.err('$error');
      return exit(ExitCode.usage.code);
    }

    final buildDirectory = p.join(
      shorebirdEnv.getShorebirdProjectRoot()!.path,
      'build',
    );
    final aotFile = File(p.join(buildDirectory, 'out.aot'));

    try {
      final shouldCodesign = argResults['codesign'] == true;
      final flutterVersionString =
          await shorebirdFlutter.getVersionAndRevision();
      final buildProgress = logger.progress(
        'Building patch with Flutter $flutterVersionString',
      );
      try {
        // If buildIpa is called with a different codesign value than the
        // release was, we will erroneously report native diffs.
        await artifactBuilder.buildIpa(
          codesign: shouldCodesign,
          exportOptionsPlist: exportOptionsPlist,
          flavor: flavor,
          target: target,
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
        final newestDillFile = artifactManager.newestAppDill();
        await artifactBuilder.buildElfAotSnapshot(
          appDillPath: newestDillFile.path,
          outFilePath: aotFile.path,
        );
      } catch (error) {
        buildProgress.fail('$error');
        rethrow;
      }

      buildProgress.complete();
    } catch (_) {
      return exit(ExitCode.software.code);
    }

    return aotFile;
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
  }) async {
    final archivePath = artifactManager.getXcarchiveDirectory()?.path;
    if (archivePath == null) {
      logger.err('Unable to find .xcarchive directory');
      return exit(ExitCode.software.code);
    }
    final releaseArtifact = await codePushClientWrapper.getReleaseArtifact(
      appId: appId,
      releaseId: releaseId,
      arch: 'xcarchive',
      platform: ReleasePlatform.ios,
    );

    final downloadProgress = logger.progress('Downloading release artifact');
    final File releaseArtifactZipFile;
    try {
      releaseArtifactZipFile = await artifactManager.downloadFile(
        Uri.parse(releaseArtifact.url),
      );
      if (!releaseArtifactZipFile.existsSync()) {
        throw Exception('Failed to download release artifact');
      }
    } catch (error) {
      downloadProgress.fail('$error');
      return exit(ExitCode.software.code);
    }
    downloadProgress.complete();

    final unzipProgress = logger.progress('Extracting release artifact');
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: releaseArtifactZipFile,
      outputDirectory: tempDir,
    );
    final releaseXcarchivePath = tempDir.path;

    unzipProgress.complete();
    final appDirectory = artifactManager.getIosAppDirectory(
      xcarchiveDirectory: Directory(releaseXcarchivePath),
    );
    if (appDirectory == null) {
      logger.err('Unable to find release artifact .app directory');
      return exit(ExitCode.software.code);
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
      );
      if (exitCode != ExitCode.success.code) return exit(exitCode);
      if (linkPercentage != null && linkPercentage < minLinkPercentage) {
        logger.warn(lowLinkPercentageWarning(linkPercentage));
      }
      _linkPercentage = linkPercentage;
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
        return exit(ExitCode.software.code);
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
    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: patchFile.path,
        hash: sha256.convert(patchBuildFile.readAsBytesSync()).toString(),
        size: patchFileSize,
      ),
    };
  }

  @override
  Future<String> extractReleaseVersionFromArtifact(File artifact) async {
    final archivePath = artifactManager.getXcarchiveDirectory()?.path;
    if (archivePath == null) {
      logger.err('Unable to find .xcarchive directory');
      exit(ExitCode.software.code);
    }

    final plistFile = File(p.join(archivePath, 'Info.plist'));
    if (!plistFile.existsSync()) {
      logger.err('No Info.plist file found at ${plistFile.path}.');
      exit(ExitCode.software.code);
    }

    final plist = Plist(file: plistFile);
    try {
      return plist.versionNumber;
    } catch (error) {
      logger.err(
        'Failed to determine release version from ${plistFile.path}: $error',
      );
      exit(ExitCode.software.code);
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
      linkPercentage: _linkPercentage,
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
  }) async {
    final patch = File(_aotOutputPath);
    final dumpDebugInfo = argResults['debug-linker'] == true &&
        (await aotTools.isLinkDebugInfoSupported());

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
    try {
      final dumpDebugInfoDir =
          dumpDebugInfo ? Directory.systemTemp.createTempSync() : null;

      linkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: patch.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        outputPath: _vmcodeOutputPath,
        workingDirectory: _buildDirectory,
        kernel: artifactManager.newestAppDill().path,
        dumpDebugInfoPath: dumpDebugInfoDir?.path,
      );

      if (dumpDebugInfo && dumpDebugInfoDir != null) {
        final debugInfoZip = await dumpDebugInfoDir.zipToTempFile();
        debugInfoZip.copySync(
          p.join(
            'build',
            _debugInfoOutputPath,
          ),
        );
      }
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      return (exitCode: ExitCode.software.code, linkPercentage: null);
    }
    linkProgress.complete();
    return (exitCode: ExitCode.success.code, linkPercentage: linkPercentage);
  }

  String get _buildDirectory => p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
      );

  String get _aotOutputPath => p.join(
        _buildDirectory,
        'out.aot',
      );

  String get _vmcodeOutputPath => p.join(
        _buildDirectory,
        'out.vmcode',
      );

  static const _linkDebugInfoFileName = 'linker_diagnostic.zip';
  String get _debugInfoOutputPath => p.join(
        _buildDirectory,
        _linkDebugInfoFileName,
      );
}