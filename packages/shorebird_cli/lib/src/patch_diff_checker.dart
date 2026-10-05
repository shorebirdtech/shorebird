// cspell:words dexdump
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/archive_analysis/file_set_diff.dart';
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

/// File names of icon fonts that Flutter tree-shakes by default in release
/// builds. Their contents depend on which icons the Dart code uses, so they
/// change whenever an icon is added or removed, even if no asset changed.
///
/// This list is intentionally not exhaustive: Flutter tree-shakes any icon
/// font used through `IconData` (e.g. fonts from `font_awesome_flutter`), but
/// only the fonts bundled by the Flutter SDK and `cupertino_icons` have names
/// that are known ahead of time.
const Set<String> treeShakenIconFontNames = {
  'MaterialIcons-Regular.otf',
  'CupertinoIcons.ttf',
};

/// Message explaining why a tree-shaken icon font shows up as an asset change.
const String treeShakenIconFontsMessage = '''
The changed icon fonts above are tree-shaken by Flutter: they only contain the
icons your Dart code uses, so they change whenever an icon is added or removed.
The patch will keep using the release's icon fonts, so icons that were not used
in the release may not render correctly.

To avoid this for future releases, disable icon tree shaking when creating the
release, e.g. `shorebird release <platform> -- --no-tree-shake-icons`.''';

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
        );

      // Show detailed DEX diff information if available.
      if (contentDiffs is AndroidFileSetDiff &&
          contentDiffs.dexDiffResults.isNotEmpty) {
        for (final dexPath
            in archiveDiffer
                .nativeFileSetDiff(contentDiffs)
                .changedPaths
                .where((p) => p.endsWith('.dex'))) {
          final dexResult = contentDiffs.dexDiffResults[dexPath];
          if (dexResult != null) {
            logger.info(yellow.wrap(dexResult.describe()));
          }
        }
        logger.info(
          yellow.wrap(
            '\nFor detailed DEX disassembly, run: dexdump -d <file>',
          ),
        );
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

If you don't know why you're seeing this error, visit our troubleshooting page at ${nativeChangesTroubleshootingUrl.toLink()}''',
        ),
      );

      if (!allowNativeChanges) {
        if (!shorebirdEnv.canAcceptUserInput) {
          logger.info(yellow.wrap(allowNativeDiffsHint));
          throw UnpatchableChangeException();
        }

        if (!logger.confirm(
          'Continue anyway?',
          hint: allowNativeDiffsHint,
        )) {
          throw UserCancelledException();
        }
      }
    }

    if (status.hasAssetChanges) {
      final assetsDiff = archiveDiffer.assetsFileSetDiff(contentDiffs);
      logger
        ..warn(
          '''Your app contains asset changes, which will not be included in the patch.''',
        )
        ..info(
          yellow.wrap(
            assetsDiff.prettyString,
          ),
        );

      if (_hasTreeShakenIconFontChange(assetsDiff)) {
        logger.info(yellow.wrap(treeShakenIconFontsMessage));
      }

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

If you don't know why you're seeing this error, visit our troubleshooting page at ${assetChangesTroubleshootingUrl.toLink()}''',
        ),
      );

      if (!allowAssetChanges) {
        if (!shorebirdEnv.canAcceptUserInput) {
          logger.info(yellow.wrap(allowAssetDiffsHint));
          throw UnpatchableChangeException();
        }

        if (!logger.confirm(
          'Continue anyway?',
          hint: allowAssetDiffsHint,
        )) {
          throw UserCancelledException();
        }
      }
    }

    return status;
  }

  /// Whether [assetsDiff] adds, removes or changes one of the
  /// [treeShakenIconFontNames].
  bool _hasTreeShakenIconFontChange(FileSetDiff assetsDiff) => [
    ...assetsDiff.addedPaths,
    ...assetsDiff.removedPaths,
    ...assetsDiff.changedPaths,
  ].any((path) => treeShakenIconFontNames.contains(p.basename(path)));
}
