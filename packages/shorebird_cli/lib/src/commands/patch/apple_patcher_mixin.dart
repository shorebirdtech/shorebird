import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:shorebird_cli/src/archive_analysis/apple_archive_differ.dart';
import 'package:shorebird_cli/src/commands/patch/patch.dart';
import 'package:shorebird_cli/src/executables/xcodebuild.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/metadata/metadata.dart';
import 'package:shorebird_cli/src/patch_diff_checker.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
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

  /// The doctor validators that should run before this Apple patch.
  List<Validator> get applePlatformValidators;

  @override
  Future<void> assertPreconditions() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkShorebirdInitialized: true,
        checkUserIsAuthenticated: true,
        validators: applePlatformValidators,
        supportedOperatingSystems: {Platform.macOS},
      );
    } on PreconditionFailedException catch (error) {
      throw ProcessExit(error.exitCode.code);
    }
  }

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
    // Check for diffs without warning about native changes, as Xcode builds
    // can be nondeterministic. So we still have some hope of alerting users of
    // unpatchable native changes, we compare the Podfile.lock hash between the
    // patch and the release.
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

    if (releaseArtifact.podfileLockHash != null &&
        localPodfileLockHash != releaseArtifact.podfileLockHash) {
      logger.warn(
        '''
Your $podfileLockRelativePath is different from the one used to build the release.
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
}
