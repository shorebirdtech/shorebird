import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// Hint shown when a user can bypass a native-diff warning interactively.
const String allowNativeDiffsHint =
    'Warning: Patches do not include native code, and a mismatch between '
    "your Dart code and the release's native code can crash your app. "
    "If you don't understand these native changes, don't ship this patch. "
    'Pass --allow-native-diffs to override this warning for this patch.';

/// Advice shown after listing dependencies whose versions changed.
const String _pinDependenciesHint =
    'A changed dependency version is a common cause of DEX changes. '
    'Pin dependency versions (or use Gradle dependency locking) so patch '
    'builds resolve the same versions as the release.\n'
    "Patches only contain Dart code, so devices keep running the release's "
    'versions of these libraries. If these version changes explain all of '
    "the differences above and your Dart code doesn't rely on them, it is "
    'safe to pass --allow-native-diffs for this patch.';

/// Hint shown when a user can bypass an asset-diff warning interactively.
const String allowAssetDiffsHint =
    'Warning: Asset changes will not be included in this patch. '
    'Pass --allow-asset-diffs to override this warning for this patch.';

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

/// A kind of change a patch can't carry.
enum UnpatchableChange {
  /// Native code changed (Java/Kotlin, Swift/Objective-C, native libraries).
  native(description: 'native code', flag: '--allow-native-diffs'),

  /// Assets changed.
  asset(description: 'assets', flag: '--allow-asset-diffs');

  const UnpatchableChange({required this.description, required this.flag});

  /// What changed, as a customer reads it ("native code", "assets").
  final String description;

  /// The flag that publishes the patch without this change.
  final String flag;
}

/// Thrown when an unpatchable change is detected in an environment where the
/// user cannot be prompted to continue.
class UnpatchableChangeException implements Exception {
  /// Creates an [UnpatchableChangeException] for [changes].
  const UnpatchableChangeException(this.changes);

  /// The changes that blocked the patch, in [UnpatchableChange] order.
  final Set<UnpatchableChange> changes;
}

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
    bool showDexDiff = false,
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

    // Where the CLI can't prompt, a change the user didn't allow fails the
    // patch, so its message is an error, not a warning.
    final canPrompt = shorebirdEnv.canAcceptUserInput;
    // Changes that fail the patch, collected so the error names every flag
    // the user needs rather than one per run.
    final blocked = <UnpatchableChange>{};

    if (status.hasNativeChanges && confirmNativeChanges) {
      const nativeMessage =
          'Your app contains native changes, which cannot be applied with a '
          'patch.';
      if (!allowNativeChanges && !canPrompt) {
        logger.err(nativeMessage);
      } else {
        logger.warn(nativeMessage);
      }
      logger.info(
        yellow.wrap(
          archiveDiffer.nativeFileSetDiff(contentDiffs).prettyString,
        ),
      );

      // Show detailed DEX diff information if available.
      var dexDetailWasHidden = false;
      if (contentDiffs is AndroidFileSetDiff &&
          contentDiffs.dexDiffResults.isNotEmpty) {
        for (final dexPath
            in archiveDiffer
                .nativeFileSetDiff(contentDiffs)
                .changedPaths
                .where((p) => p.endsWith('.dex'))) {
          final dexResult = contentDiffs.dexDiffResults[dexPath];
          if (dexResult != null) {
            if (dexResult.hasHiddenCodeDiff) dexDetailWasHidden = true;
            logger.info(
              yellow.wrap(dexResult.describe(showFullCodeDiff: showDexDiff)),
            );
          }
        }
        if (!showDexDiff && dexDetailWasHidden) {
          logger.info(
            yellow.wrap(
              '\nPass --show-dex-diff to see every differing instruction. '
              'That output includes every instruction in full and any '
              'string constants or payload data they carry.',
            ),
          );
        }
      }

      // Name the dependencies whose versions moved, which usually explains a
      // DEX change the developer didn't make.
      if (contentDiffs is AndroidFileSetDiff &&
          contentDiffs.dependencyVersionChanges.isNotEmpty) {
        logger.info(
          yellow.wrap(
            [
              '\nDependency versions differ from the release:',
              for (final change in contentDiffs.dependencyVersionChanges)
                '  ${change.describe()}',
              _pinDependenciesHint,
            ].join('\n'),
          ),
        );
      }

      logger.info(
        yellow.wrap(
          '''

If you don't know why you're seeing this, visit our troubleshooting page at ${nativeChangesTroubleshootingUrl.toLink()}''',
        ),
      );

      if (!allowNativeChanges) {
        if (!canPrompt) {
          blocked.add(UnpatchableChange.native);
        } else if (!logger.confirm(
          'Continue anyway?',
          hint: allowNativeDiffsHint,
        )) {
          throw UserCancelledException();
        }
      }
    }

    if (status.hasAssetChanges) {
      const assetMessage =
          'Your app contains asset changes, which will not be included in the '
          'patch.';
      if (!allowAssetChanges && !canPrompt) {
        logger.err(assetMessage);
      } else {
        logger.warn(assetMessage);
      }
      logger.info(
        yellow.wrap(archiveDiffer.assetsFileSetDiff(contentDiffs).prettyString),
      );

      final diffs = await archiveDiffer.availableAssetDiffs(
        fileSetDiff: contentDiffs,
        oldArchivePath: releaseArchive.path,
        newArchivePath: localArchive.path,
      );
      if (diffs.isNotEmpty) {
        logger.info(diffs);
      }

      logger.info(
        yellow.wrap(
          '''

If you don't know why you're seeing this, visit our troubleshooting page at ${assetChangesTroubleshootingUrl.toLink()}''',
        ),
      );

      if (!allowAssetChanges) {
        if (!canPrompt) {
          blocked.add(UnpatchableChange.asset);
        } else if (!logger.confirm(
          'Continue anyway?',
          hint: allowAssetDiffsHint,
        )) {
          throw UserCancelledException();
        }
      }
    }

    if (blocked.isNotEmpty) throw UnpatchableChangeException(blocked);

    return status;
  }
}
