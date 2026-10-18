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
  /// The name of the file that gen_snapshot writes split debug info to. The
  /// filename is iOS-flavored historically; we keep it for both iOS and macOS
  /// so existing release artifacts remain referenceable.
  static const splitDebugInfoFileName = 'app.ios-arm64.symbols';

  /// Resolves the absolute path inside [directory] where gen_snapshot should
  /// write the split debug info file.
  static String saveDebuggingInfoPath(String directory) =>
      p.join(p.absolute(directory), splitDebugInfoFileName);

  /// The additional gen_snapshot arguments to pass when building the patch
  /// with `--split-debug-info`.
  static List<String> splitDebugInfoArgs(String? splitDebugInfoPath) =>
      splitDebugInfoPath != null
      ? [
          '--dwarf-stack-traces',
          '--resolve-dwarf-paths',
          '--save-debugging-info=${saveDebuggingInfoPath(splitDebugInfoPath)}',
        ]
      : <String>[];

  /// Where the patch build's kernel file is copied so that it can be used to
  /// link the patch.
  String get appDillCopyPath =>
      p.join(shorebirdEnv.buildDirectory.path, 'app.dill');

  /// The gen_snapshot arguments for `--split-debug-info` and obfuscation,
  /// shared by the ELF snapshot build and the linker.
  List<String> get appleGenSnapshotArgs => [
    ...splitDebugInfoArgs(splitDebugInfoPath),
    ...obfuscationGenSnapshotArgs,
  ];

  /// Builds an ELF AOT snapshot of [appDillPath] at [outFilePath] with
  /// [genSnapshotArtifact], creating the split debug info directory first if
  /// one was requested.
  Future<void> buildAppleElfAotSnapshot({
    required String appDillPath,
    required String outFilePath,
    required ShorebirdArtifact genSnapshotArtifact,
  }) async {
    if (splitDebugInfoPath != null) {
      Directory(splitDebugInfoPath!).createSync(recursive: true);
    }
    await artifactBuilder.buildElfAotSnapshot(
      appDillPath: appDillPath,
      outFilePath: outFilePath,
      genSnapshotArtifact: genSnapshotArtifact,
      additionalArgs: appleGenSnapshotArgs,
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
    String? packageResolvedHash,
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
          patchBaseProgress.fail('$error');
          throw ProcessExit(ExitCode.software.code);
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
        packageResolvedHash: packageResolvedHash,
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

  /// The hash of the pins in the local Swift Package Manager Package.resolved
  /// for this Apple platform, or null if there is none. See
  /// [ShorebirdEnv.packageResolvedHash].
  String? get localPackageResolvedHash;

  /// Project-relative path of the Package.resolved surfaced in the warning.
  String get packageResolvedRelativePath;

  @override
  Future<DiffStatus> assertUnpatchableDiffs({
    required ReleaseArtifact releaseArtifact,
    required File releaseArchive,
    required File patchArchive,
  }) async {
    // Check for diffs without warning about native changes, as Xcode builds
    // can be nondeterministic. So we still have some hope of alerting users of
    // unpatchable native changes, we compare the Podfile.lock (CocoaPods) and
    // Package.resolved (Swift Package Manager) hashes between the patch and
    // the release. Each is checked only if the release recorded it; releases
    // made before the CLI recorded packageResolvedHash skip that check.
    final diffStatus = await patchDiffChecker
        .confirmUnpatchableDiffsIfNecessary(
          localArchive: patchArchive,
          releaseArchive: releaseArchive,
          archiveDiffer: const AppleArchiveDiffer(),
          allowAssetChanges: allowAssetDiffs,
          allowNativeChanges: allowNativeDiffs,
          confirmNativeChanges: false,
        );

    if (!diffStatus.hasNativeChanges) return diffStatus;

    final differences = [
      ?_lockFileDifference(
        path: podfileLockRelativePath,
        releaseHash: releaseArtifact.podfileLockHash,
        localHash: localPodfileLockHash,
      ),
      ?_lockFileDifference(
        path: packageResolvedRelativePath,
        releaseHash: releaseArtifact.packageResolvedHash,
        localHash: localPackageResolvedHash,
      ),
    ];

    if (differences.isNotEmpty) {
      logger.warn(
        '''
${differences.join('\n')}
This may indicate that the patch contains native changes, which cannot be applied with a patch. Proceeding may result in unexpected behavior or crashes.''',
      );

      if (!allowNativeDiffs) {
        if (!shorebirdEnv.canAcceptUserInput) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyway?', hint: allowNativeDiffsHint)) {
          throw UserCancelledException();
        }
      }
    }

    return diffStatus;
  }

  /// Describes how the lockfile at [path] differs from the release's, or
  /// returns null if it doesn't or the release recorded no hash for it.
  String? _lockFileDifference({
    required String path,
    required String? releaseHash,
    required String? localHash,
  }) {
    if (releaseHash == null || localHash == releaseHash) return null;
    if (localHash == null) {
      return 'This project has no $path, but the release was built with one.';
    }
    return 'Your $path is different from the one used to build the release.';
  }
}
