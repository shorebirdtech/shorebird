import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Shared lookup of a release's patches for the `patches` subcommands.
mixin PatchLookup on ShorebirdCommand {
  /// Fetches release [releaseVersion] of [appId] and its patches.
  ///
  /// In `--json` mode a failed fetch is reported as a `fetch_failed` error
  /// with [fetchFailedMessage] (by default "Failed to fetch patches for
  /// release ...") and its exit code is returned; otherwise the failure is
  /// rethrown.
  ///
  /// Returns the release and its patches on success, or `errorCode` after
  /// reporting the failure.
  Future<({Release? release, List<ReleasePatch> patches, int? errorCode})>
  fetchReleasePatches({
    required String appId,
    required String releaseVersion,
    String? fetchFailedMessage,
  }) async {
    try {
      final release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
      final patches = await codePushClientWrapper.getReleasePatches(
        appId: appId,
        releaseId: release.id,
      );
      return (release: release, patches: patches, errorCode: null);
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message:
              fetchFailedMessage ??
              'Failed to fetch patches for release "$releaseVersion".',
        );
        return (
          release: null,
          patches: <ReleasePatch>[],
          errorCode: e.exitCode,
        );
      }
      rethrow;
    }
  }

  /// Finds patch [patchNumber] among [patches] of release [releaseVersion].
  ///
  /// When there is no such patch, reports it as a usage error (listing the
  /// available patch numbers in human-readable mode) and returns its exit
  /// code.
  ({ReleasePatch? patch, int? errorCode}) findPatchOrReport({
    required List<ReleasePatch> patches,
    required int patchNumber,
    required String releaseVersion,
  }) {
    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    if (patch != null) return (patch: patch, errorCode: null);

    if (isJsonMode) {
      emitJsonError(
        code: JsonErrorCode.usageError,
        message:
            'No patch found with number $patchNumber '
            'for release "$releaseVersion".',
      );
    } else {
      logger
        ..err('No patch found with number $patchNumber')
        ..info(
          'Available patches: ${patches.map((p) => p.number).join(', ')}',
        );
    }
    return (patch: null, errorCode: ExitCode.usage.code);
  }
}
