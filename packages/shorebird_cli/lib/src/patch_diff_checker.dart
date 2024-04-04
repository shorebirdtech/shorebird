import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// {@template diff_status}
/// Describes the types of changes that have been detected between a patch
/// and its release.
/// {@endtemplate}
class DiffStatus {
  /// {@macro diff_status}
  DiffStatus({
    required this.hasAssetChanges,
    required this.hasNativeChanges,
  });

  /// Whether the patch contains asset changes.
  final bool hasAssetChanges;

  /// Whether the patch contains native code changes.
  final bool hasNativeChanges;
}

/// Thrown when an unpatchable change is detected in an environment where the
/// user cannot be prompted to continue.
class UnpatchableChangeException implements Exception {}

/// Thrown when the user cancels after being prompted to continue.
class UserCancelledException implements Exception {}

/// A reference to a [PatchDiffChecker] instance.
ScopedRef<PatchDiffChecker> patchDiffCheckerRef = create(PatchDiffChecker.new);

// The [PatchVerifier] instance available in the current zone.
PatchDiffChecker get patchDiffChecker => read(patchDiffCheckerRef);

/// {@template patch_verifier}
/// Verifies that a patch can successfully be applied to a release artifact.
/// {@endtemplate}
class PatchDiffChecker {
  /// Zips the contents of [localArtifactDirectory] to a temporary file and
  /// forwards to [confirmUnpatchableDiffsIfNecessary].
  Future<DiffStatus> zipAndConfirmUnpatchableDiffsIfNecessary({
    required Directory localArtifactDirectory,
    required File releaseArtifact,
    required ArchiveDiffer archiveDiffer,
    required bool allowAssetChanges,
    required bool allowNativeChanges,
  }) async {
    final zipProgress = logger.progress('Compressing archive');
    final zippedFile = await localArtifactDirectory.zipToTempFile();
    zipProgress.complete();

    return confirmUnpatchableDiffsIfNecessary(
      localArtifact: zippedFile,
      releaseArtifact: releaseArtifact,
      archiveDiffer: archiveDiffer,
      allowAssetChanges: allowAssetChanges,
      allowNativeChanges: allowNativeChanges,
    );
  }

  /// Checks for differences that could cause issues when applying the
  /// [localArtifact] patch to the [releaseArtifact].
  Future<DiffStatus> confirmUnpatchableDiffsIfNecessary({
    required File localArtifact,
    required File releaseArtifact,
    required ArchiveDiffer archiveDiffer,
    required bool allowAssetChanges,
    required bool allowNativeChanges,
  }) async {
    final progress =
        logger.progress('Verifying patch can be applied to release');

    final contentDiffs = await archiveDiffer.changedFiles(
      releaseArtifact.path,
      localArtifact.path,
    );
    progress.complete();

    final status = DiffStatus(
      hasAssetChanges:
          archiveDiffer.containsPotentiallyBreakingAssetDiffs(contentDiffs),
      hasNativeChanges:
          archiveDiffer.containsPotentiallyBreakingNativeDiffs(contentDiffs),
    );

    if (status.hasNativeChanges) {
      logger
        ..warn(
          '''Your app contains native changes, which cannot be applied with a patch.''',
        )
        ..info(
          yellow.wrap(
            archiveDiffer.nativeFileSetDiff(contentDiffs).prettyString,
          ),
        )
        ..info(
          yellow.wrap('''

If you don't know why you're seeing this error, visit our troublshooting page at ${link(uri: Uri.parse('https://docs.shorebird.dev/troubleshooting#unexpected-native-changes'))}'''),
        );

      if (!allowNativeChanges) {
        if (!shorebirdEnv.canAcceptUserInput) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          throw UserCancelledException();
        }
      }
    }

    if (status.hasAssetChanges) {
      logger
        ..warn(
          '''Your app contains asset changes, which will not be included in the patch.''',
        )
        ..info(
          yellow.wrap(
            archiveDiffer.assetsFileSetDiff(contentDiffs).prettyString,
          ),
        );

      if (!allowAssetChanges) {
        if (!shorebirdEnv.canAcceptUserInput) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          throw UserCancelledException();
        }
      }
    }

    return status;
  }
}
