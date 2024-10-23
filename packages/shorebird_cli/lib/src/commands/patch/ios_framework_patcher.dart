import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/archive_analysis/ios_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/release_type.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template ios_framework_patcher}
/// Functions to patch an iOS Framework release.
/// {@endtemplate}
class IosFrameworkPatcher extends Patcher {
  /// {@macro ios_framework_patcher}
  IosFrameworkPatcher({
    required super.argResults,
    required super.argParser,
    required super.flavor,
    required super.target,
  });

  String get _vmcodeOutputPath => p.join(buildDirectory.path, 'out.vmcode');

  String get _appDillCopyPath => p.join(buildDirectory.path, 'app.dill');

  @override
  String get primaryReleaseArtifactArch => 'xcframework';

  @override
  ReleaseType get releaseType => ReleaseType.iosFramework;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  /// The last build link percentage.
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
      throw ProcessExit(e.exitCode.code);
    }
  }

  @override
  Future<void> assertArgsAreValid() async {
    if (!argResults.wasParsed('release-version')) {
      logger.err('Missing required argument: --release-version');
      throw ProcessExit(ExitCode.usage.code);
    }
  }

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) =>
      patchDiffChecker.confirmUnpatchableDiffsIfNecessary(
        localArchive: patchArchive,
        releaseArchive: releaseArchive,
        archiveDiffer: const IosArchiveDiffer(),
        allowAssetChanges: allowAssetDiffs,
        allowNativeChanges: allowNativeDiffs,
      );

  @override
  Future<File> buildPatchArtifact({String? releaseVersion}) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();
    final buildProgress = logger.progress(
      'Building patch with Flutter $flutterVersionString',
    );

    final IosFrameworkBuildResult buildResult;
    try {
      buildResult = await artifactBuilder.buildIosFramework(
        args: argResults.forwardedArgs,
      );
    } on ArtifactBuildException catch (error) {
      buildProgress.fail(error.message);
      throw ProcessExit(ExitCode.software.code);
    }
    try {
      if (splitDebugInfoPath != null) {
        Directory(splitDebugInfoPath!).createSync(recursive: true);
      }
      await artifactBuilder.buildElfAotSnapshot(
        appDillPath: buildResult.kernelFile.path,
        outFilePath: p.join(
          shorebirdEnv.getShorebirdProjectRoot()!.path,
          'build',
          'out.aot',
        ),
        additionalArgs: IosPatcher.splitDebugInfoArgs(splitDebugInfoPath),
      );
    } catch (error) {
      buildProgress.fail('$error');
      throw ProcessExit(ExitCode.software.code);
    }

    buildProgress.complete();

    // Copy the kernel file to the build directory so that it can be used
    // to generate a patch.
    buildResult.kernelFile.copySync(_appDillCopyPath);

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
  Future<String> extractReleaseVersionFromArtifact(File artifact) {
    // Not implemented - release version must be specified by the user.
    throw UnimplementedError(
      'Release version must be specified using --release-version.',
    );
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

  Future<void> _runLinker({
    required File aotSnapshot,
    required File releaseArtifact,
  }) async {
    if (!aotSnapshot.existsSync()) {
      logger.err('Unable to find patch AOT file at ${aotSnapshot.path}');
      throw ProcessExit(ExitCode.software.code);
    }

    final analyzeSnapshot = File(
      shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshot,
      ),
    );

    if (!analyzeSnapshot.existsSync()) {
      logger.err('Unable to find analyze_snapshot at ${analyzeSnapshot.path}');
      throw ProcessExit(ExitCode.software.code);
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
        kernel: _appDillCopyPath,
        outputPath: _vmcodeOutputPath,
        workingDirectory: buildDirectory.path,
        additionalArgs: IosPatcher.splitDebugInfoArgs(splitDebugInfoPath),
      );
    } catch (error) {
      linkProgress.fail('Failed to link AOT files: $error');
      throw ProcessExit(ExitCode.software.code);
    }

    linkProgress.complete();
  }
}
