import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/ios_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
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

/// {@template ios_framework_patcher}
/// Functions to patch an iOS Framework release.
/// {@endtemplate}
class IosFrameworkPatcher extends Patcher {
  /// {@macro ios_framework_patcher}
  IosFrameworkPatcher({
    required super.argResults,
    required super.flavor,
    required super.target,
  });

  String get _vmcodeOutputPath => p.join(buildDirectory.path, 'out.vmcode');

  @override
  ArchiveDiffer get archiveDiffer => IosArchiveDiffer();

  @override
  String get primaryReleaseArtifactArch => 'xcframework';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  @visibleForTesting
  double? lastBuildLinkPercentage;

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
  }

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      exit(ExitCode.usage.code);
    }
  }

  @override
  Future<File> buildPatchArtifact() async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress = logger.progress(
      'Building patch with Flutter $flutterVersionString',
    );
    try {
      await artifactBuilder.buildIosFramework(
        args: argResults.forwardedArgs,
      );
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      exit(ExitCode.software.code);
    }
    try {
      final newestDillFile = artifactManager.newestAppDill();
      await artifactBuilder.buildElfAotSnapshot(
        appDillPath: newestDillFile.path,
        outFilePath: p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'out.aot',
        ),
      );
    } catch (error) {
      buildProgress.fail('$error');
      exit(ExitCode.software.code);
    }

    buildProgress.complete();

    return Directory(
      p.join(
        artifactManager.getAppXcframeworkDirectory().path,
        ArtifactManager.appXcframeworkName,
      ),
    ).zipToTempFile();
  }

  @override
  Future<Map<Arch, PatchArtifactBundle>> createPatchArtifacts({
    required String appId,
    required int releaseId,
    required File releaseArtifact,
  }) async {
    final unzipProgress = logger.progress('Extracting release artifact');
    final tempDir = Directory.systemTemp.createTempSync();
    await artifactManager.extractZip(
      zipFile: releaseArtifact,
      outputDirectory: tempDir,
    );
    final releaseXcframeworkPath = tempDir.path;

    unzipProgress
        .complete('Extracted release artifact to $releaseXcframeworkPath');
    final releaseArtifactFile = File(
      p.join(
        releaseXcframeworkPath,
        'ios-arm64',
        'App.framework',
        'App',
      ),
    );

    final aotSnapshotFile = File(
      p.join(
        shorebirdEnv.getShorebirdProjectRoot()!.path,
        'build',
        'out.aot',
      ),
    );
    final useLinker = AotTools.usesLinker(shorebirdEnv.flutterRevision);
    if (useLinker) {
      await _runLinker(
        aotSnapshot: aotSnapshotFile,
        releaseArtifact: releaseArtifactFile,
      );
    }

    final patchBuildFile =
        useLinker ? File(_vmcodeOutputPath) : aotSnapshotFile;
    final File patchFile;
    if (await aotTools.isGeneratePatchDiffBaseSupported()) {
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
        exit(ExitCode.software.code);
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

    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: patchFile.path,
        hash: sha256.convert(patchBuildFile.readAsBytesSync()).toString(),
        size: patchFile.statSync().size,
      ),
    };
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

  Future<void> _runLinker({
    required File aotSnapshot,
    required File releaseArtifact,
  }) async {
    if (!aotSnapshot.existsSync()) {
      logger.err('Unable to find patch AOT file at ${aotSnapshot.path}');
      exit(ExitCode.software.code);
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      exit(ExitCode.software.code);
    }

    final genSnapshot = shorebirdArtifacts.getArtifactPath(
      artifact: ShorebirdArtifact.genSnapshot,
    );

    final linkProgress = logger.progress('Linking AOT files');
    try {
      lastBuildLinkPercentage = await aotTools.link(
        base: releaseArtifact.path,
        patch: aotSnapshot.path,
        analyzeSnapshot: analyzeSnapshot.path,
        genSnapshot: genSnapshot,
        kernel: artifactManager.newestAppDill().path,
        outputPath: _vmcodeOutputPath,
        workingDirectory: buildDirectory.path,
      );
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      exit(ExitCode.software.code);
    }

    linkProgress.complete();
  }
}
