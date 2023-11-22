import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive/archive.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

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
  Future<void> zipAndConfirmUnpatchableDiffsIfNecessary({
    required Directory localArtifactDirectory,
    required Uri releaseArtifactUrl,
    required ArchiveDiffer archiveDiffer,
    required bool force,
  }) async {
    final zipProgress = logger.progress('Compressing archive');
    final zippedFile = await localArtifactDirectory.zipToTempFile();
    zipProgress.complete();

    return confirmUnpatchableDiffsIfNecessary(
      localArtifact: zippedFile,
      releaseArtifactUrl: releaseArtifactUrl,
      archiveDiffer: archiveDiffer,
      force: force,
    );
  }

  /// Downloads the release artifact at [releaseArtifactUrl] and checks for
  /// differences that could cause issues when applying the patch represented by
  /// [localArtifact].
  Future<void> confirmUnpatchableDiffsIfNecessary({
    required File localArtifact,
    required Uri releaseArtifactUrl,
    required ArchiveDiffer archiveDiffer,
    required bool force,
  }) async {
    final progress =
        logger.progress('Verifying patch can be applied to release');

    final request = http.Request('GET', releaseArtifactUrl);
    final response = await httpClient.send(request);

    if (response.statusCode != HttpStatus.ok) {
      progress.fail();
      throw Exception(
        '''Failed to download release artifact: ${response.statusCode} ${response.reasonPhrase}''',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp();
    final releaseArtifact = File(p.join(tempDir.path, 'release.artifact'));
    await releaseArtifact.openWrite().addStream(response.stream);

    final contentDiffs = archiveDiffer.changedFiles(
      releaseArtifact.path,
      localArtifact.path,
    );
    progress.complete();

    if (archiveDiffer.containsPotentiallyBreakingNativeDiffs(contentDiffs)) {
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

      if (!force) {
        if (shorebirdEnv.isRunningOnCI) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          throw UserCancelledException();
        }
      }
    }

    if (archiveDiffer.containsPotentiallyBreakingAssetDiffs(contentDiffs)) {
      logger
        ..warn(
          '''Your app contains asset changes, which will not be included in the patch.''',
        )
        ..info(
          yellow.wrap(
            archiveDiffer.assetsFileSetDiff(contentDiffs).prettyString,
          ),
        );

      if (!force) {
        if (shorebirdEnv.isRunningOnCI) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          throw UserCancelledException();
        }
      }
    }
  }
}
