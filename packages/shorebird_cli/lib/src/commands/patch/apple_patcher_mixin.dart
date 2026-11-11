import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/artifact_builder/artifact_builder.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/commands/build_preconditions.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/executables/aot_tools.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_artifacts.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Shared logic for Apple-platform patchers (iOS, macOS, iOS framework).
///
/// Concrete patchers supply the platform-specific validators and (for iOS and
/// macOS) the local Podfile.lock state used to detect native diffs that
/// `package:archive` can't reliably catch in a nondeterministic Xcode build.
mixin ApplePatcherMixin on Patcher {
  /// The name of the file that gen_snapshot writes an iOS patch's split debug
  /// info to: the name `flutter build ipa` gives the release's.
  static const splitDebugInfoFileName = 'app.ios-arm64.symbols';

  /// Resolves the absolute path inside [directory] where gen_snapshot should
  /// write the split debug info file named [fileName].
  static String saveDebuggingInfoPath(
    String directory, {
    String fileName = splitDebugInfoFileName,
  }) => p.join(p.absolute(directory), fileName);

  /// The additional gen_snapshot arguments to pass when building the patch
  /// with `--split-debug-info`, writing the debug info to [fileName] in
  /// [splitDebugInfoPath].
  static List<String> splitDebugInfoArgs(
    String? splitDebugInfoPath, {
    String fileName = splitDebugInfoFileName,
  }) => splitDebugInfoPath != null
      ? [
          '--dwarf-stack-traces',
          '--resolve-dwarf-paths',
          '--save-debugging-info=${saveDebuggingInfoPath(
            splitDebugInfoPath,
            fileName: fileName,
          )}',
        ]
      : <String>[];

  /// Where the patch build's kernel file is copied so that it can be used to
  /// link the patch.
  String get appDillCopyPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'app.dill');

  /// The gen_snapshot arguments for `--split-debug-info` and obfuscation,
  /// shared by the ELF snapshot build and the linker.
  List<String> get appleGenSnapshotArgs => _appleGenSnapshotArgs();

  List<String> _appleGenSnapshotArgs({
    String splitDebugInfoFileName = splitDebugInfoFileName,
  }) => [
    ...splitDebugInfoArgs(splitDebugInfoPath, fileName: splitDebugInfoFileName),
    ...obfuscationGenSnapshotArgs,
  ];

  /// Builds an ELF AOT snapshot of [appDillPath] at [outFilePath] with
  /// [genSnapshotArtifact], creating the split debug info directory first if
  /// one was requested. A build that runs gen_snapshot once per architecture
  /// (macOS) gives each run its own [splitDebugInfoFileName], so one run
  /// doesn't overwrite another's symbols.
  Future<void> buildAppleElfAotSnapshot({
    required String appDillPath,
    required String outFilePath,
    required ShorebirdArtifact genSnapshotArtifact,
    String splitDebugInfoFileName = ApplePatcherMixin.splitDebugInfoFileName,
  }) async {
    if (splitDebugInfoPath != null) {
      Directory(splitDebugInfoPath!).createSync(recursive: true);
    }
    await artifactBuilder.buildElfAotSnapshot(
      appDillPath: appDillPath,
      outFilePath: outFilePath,
      genSnapshotArtifact: genSnapshotArtifact,
      additionalArgs: _appleGenSnapshotArgs(
        splitDebugInfoFileName: splitDebugInfoFileName,
      ),
    );
  }

  /// The doctor validators that should run before this Apple patch.
  List<Validator> get applePlatformValidators;

  @override
  Future<void> assertPreconditions() => assertBuildPreconditions(
    validators: applePlatformValidators,
    supportedOperatingSystems: {NativePlatform.macOS},
  );

  @override
  Future<CreatePatchMetadata> updatedCreatePatchMetadata(
    CreatePatchMetadata metadata,
  ) async => metadata.copyWith(
    linkPercentage: linkPercentage,
    linkMetadata: linkMetadata,
    environment: metadata.environment.copyWith(
      xcodeVersion: await xcodeBuild.version(),
    ),
  );

  /// Linker output (link map / version info) attached to patch metadata.
  /// Returns `null` if the platform does not use a linker or if the linking
  /// step has not yet been run.
  Json? get linkMetadata => null;
}

/// Links an iOS patch against its release and packages it, shared by the iOS
/// and iOS framework patchers.
mixin AppleLinkerPatcherMixin on Patcher, ApplePatcherMixin {
  /// Where the patch's ELF AOT snapshot is written.
  String get aotOutputPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'out.aot');

  /// Where the linker writes the patch's vmcode.
  String get vmcodeOutputPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'out.vmcode');

  /// The last build's link percentage.
  @visibleForTesting
  double? lastBuildLinkPercentage;

  /// The last build's link metadata.
  @visibleForTesting
  Json? lastBuildLinkMetadata;

  @override
  double? get linkPercentage => lastBuildLinkPercentage;

  @override
  Json? get linkMetadata => lastBuildLinkMetadata;

  /// Links the patch against [releaseArtifactFile] (the release's
  /// `App.framework/App`), diffs it against the release when supported, and
  /// returns the signed arm64 patch bundle.
  Future<Map<Arch, PatchArtifactBundle>> linkAndBundlePatch({
    required File releaseArtifactFile,
    required Directory releaseSupplementDir,
    String? podfileLockHash,
  }) async {
    final useLinker = AotTools.usesLinker(shorebirdEnv.flutterRevision);
    if (useLinker) {
      apple.copySupplementFilesToSnapshotDirs(
        releaseSupplementDir: releaseSupplementDir,
        releaseSnapshotDir: releaseArtifactFile.parent,
        patchSupplementDir: shorebirdEnv.iosSupplementDirectory,
        patchSnapshotDir: shorebirdEnv.buildDirectory,
      );

      final result = await apple.runLinker(
        kernelFile: File(appDillCopyPath),
        releaseArtifact: releaseArtifactFile,
        splitDebugInfoArgs: appleGenSnapshotArgs,
        aotOutputFile: File(aotOutputPath),
        vmCodeFile: File(vmcodeOutputPath),
        ddMaxBytes: ddMaxBytes,
      );
      final linkPercentage = result.linkPercentage;
      final exitCode = result.exitCode;
      if (exitCode != ExitCode.success.code) throw ProcessExit(exitCode);
      if (linkPercentage != null &&
          linkPercentage < Patcher.linkPercentageWarningThreshold) {
        logger.warn(Patcher.lowLinkPercentageWarning(linkPercentage));
      }
      lastBuildLinkPercentage = linkPercentage;
      lastBuildLinkMetadata = result.linkMetadata;
    }

    final patchBuildFile = File(useLinker ? vmcodeOutputPath : aotOutputPath);

    final File patchFile;
    if (useLinker && await aotTools.isGeneratePatchDiffBaseSupported()) {
      final patchBaseProgress = logger.progress('Generating patch diff base');
      final analyzeSnapshotPath = shorebirdArtifacts.getArtifactPath(
        artifact: ShorebirdArtifact.analyzeSnapshotIos,
      );

      final patchBaseDirectory = Directory.systemTemp.createTempSync();
      try {
        final File patchBaseFile;
        try {
          // If the aot_tools executable supports the dump_blobs command, we
          // can generate a stable diff base and use that to create a patch.
          patchBaseFile = await aotTools.generatePatchDiffBase(
            analyzeSnapshotPath: analyzeSnapshotPath,
            releaseSnapshot: releaseArtifactFile,
            outputDirectory: patchBaseDirectory,
          );
          patchBaseProgress.complete();
        } on Exception catch (error) {
          patchBaseProgress.fail();
          throw CommandError(
            message: 'Failed to generate the patch diff base: $error',
            exitCode: ExitCode.software,
          );
        }

        patchFile = File(
          await artifactManager.createDiff(
            releaseArtifactPath: patchBaseFile.path,
            patchArtifactPath: patchBuildFile.path,
          ),
        );
      } finally {
        patchBaseDirectory.deleteTemporarySync();
      }
    } else {
      patchFile = patchBuildFile;
    }

    final patchFileSize = patchFile.statSync().size;
    final hash = sha256.convert(patchBuildFile.readAsBytesSync()).toString();
    final hashSignature = await signHash(hash);

    return {
      Arch.arm64: PatchArtifactBundle(
        arch: 'aarch64',
        path: patchFile.path,
        hash: hash,
        size: patchFileSize,
        hashSignature: hashSignature,
        podfileLockHash: podfileLockHash,
      ),
    };
  }
}

/// Adds Podfile.lock-based native-change detection to [ApplePatcherMixin].
/// Implemented by iOS and macOS patchers; the iOS framework patcher doesn't
/// emit a Podfile.lock.
mixin ApplePodfileLockPatcherMixin on Patcher, ApplePatcherMixin {
  /// SHA-256 of the local Podfile.lock for this Apple platform, or null if
  /// no Podfile.lock exists.
  String? get localPodfileLockHash;

  /// Project-relative path of the Podfile.lock surfaced in the warning.
  String get podfileLockRelativePath;

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    final diffStatus = await patchDiffChecker
        .confirmUnpatchableDiffsIfNecessary(
          localArchive: patchArchive,
          releaseArchive: releaseArchive,
          archiveDiffer: const AppleArchiveDiffer(),
          allowAssetChanges: allowAssetDiffs,
          allowNativeChanges: allowNativeDiffs,
        );

    final podfileLockChanged =
        releaseArtifact.podfileLockHash != null &&
        localPodfileLockHash != releaseArtifact.podfileLockHash;

    if (!diffStatus.hasNativeChanges) {
      if (podfileLockChanged) {
        logger.info(
          'Your $podfileLockRelativePath changed from the release, but all '
          'compiled native binaries are identical.',
        );
      }
      return diffStatus;
    }

    if (podfileLockChanged) {
      logger.warn(
        '''
Your $podfileLockRelativePath is different from the one used to build the release.
This may indicate that the patch contains native changes, which cannot be applied with a patch. Proceeding may result in unexpected behavior or crashes.''',
      );
    }

    return diffStatus;
  }
}
