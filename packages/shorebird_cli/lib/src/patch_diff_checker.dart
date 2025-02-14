import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// {@template diff_status}
/// Describes the types of changes that have been detected between a patch
/// and its release.
/// {@endtemplate}
class DiffStatus {
  /// {@macro diff_status}
  const DiffStatus({
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

/// The [PatchDiffChecker] instance available in the current zone.
PatchDiffChecker get patchDiffChecker => read(patchDiffCheckerRef);

/// {@template patch_verifier}
/// Verifies that a patch can successfully be applied to a release artifact.
/// {@endtemplate}
class PatchDiffChecker {
  /// Checks for differences that could cause issues when applying the
  /// [localArchive] patch to the [releaseArchive].
  Future<DiffStatus> confirmUnpatchableDiffsIfNecessary({
    required File localArchive,
    required File releaseArchive,
    required ArchiveDiffer archiveDiffer,
    required bool allowAssetChanges,
    required bool allowNativeChanges,
    bool confirmNativeChanges = true,
  }) async {
    final progress = logger.progress(
      'Verifying patch can be applied to release',
    );

    final contentDiffs = await archiveDiffer.changedFiles(
      releaseArchive.path,
      localArchive.path,
    );
    progress.complete();

    final status = DiffStatus(
      hasAssetChanges: archiveDiffer.containsPotentiallyBreakingAssetDiffs(
        contentDiffs,
      ),
      hasNativeChanges: archiveDiffer.containsPotentiallyBreakingNativeDiffs(
        contentDiffs,
      ),
    );

    if (status.hasNativeChanges && confirmNativeChanges) {
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
          yellow.wrap(
            '''

If you don't know why you're seeing this error, visit our troubleshooting page at ${troubleshootingUrl.toLink()}''',
          ),
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
