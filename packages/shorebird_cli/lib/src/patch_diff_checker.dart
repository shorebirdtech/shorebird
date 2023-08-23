import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive_analysis/archive_differ.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// Thrown when an unpatchable change is detected in an environment where the
/// user cannot be prompted to continue.
class UnpatchableChangeException implements Exception {}

/// A reference to a [PatchDiffChecker] instance.
ScopedRef<PatchDiffChecker> patchDiffCheckerRef = create(PatchDiffChecker.new);

// The [PatchVerifier] instance available in the current zone.
PatchDiffChecker get patchDiffChecker => read(patchDiffCheckerRef);

/// {@template patch_verifier}
/// Verifies that a patch can successfully be applied to a release artifact.
/// {@endtemplate}
class PatchDiffChecker {
  /// {@macro patch_verifier}
  PatchDiffChecker({http.Client? httpClient})
      // coverage:ignore-start
      : _httpClient = httpClient ??
            retryingHttpClient(LoggingClient(httpClient: http.Client()));
  // coverage:ignore-end

  final http.Client _httpClient;

  /// Downloads the release artifact at [releaseArtifactUrl] and checks for
  /// differences that could cause issues when applying the patch represented by
  /// [localArtifact].
  Future<bool> confirmUnpatchableDiffsIfNecessary({
    required File localArtifact,
    required Uri releaseArtifactUrl,
    required ArchiveDiffer archiveDiffer,
    required bool force,
  }) async {
    final progress =
        logger.progress('Verifying patch can be applied to release');

    final request = http.Request('GET', releaseArtifactUrl);
    final response = await _httpClient.send(request);

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
          '''The release artifact contains native changes, which cannot be applied with a patch.''',
        )
        ..info(
          yellow.wrap(
            archiveDiffer.nativeFileSetDiff(contentDiffs).prettyString,
          ),
        );

      if (!force) {
        if (shorebirdEnv.isRunningOnCI) {
          throw UnpatchableChangeException();
        }

        if (!logger.confirm('Continue anyways?')) {
          return false;
        }
      }
    }

    if (archiveDiffer.containsPotentiallyBreakingAssetDiffs(contentDiffs)) {
      logger
        ..warn(
          '''The release artifact contains asset changes, which will not be included in the patch.''',
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
          return false;
        }
      }
    }

    return true;
  }
}
