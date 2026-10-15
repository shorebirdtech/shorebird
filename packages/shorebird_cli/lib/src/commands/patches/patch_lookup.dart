import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
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
    late final Release release;
    late final List<ReleasePatch> patches;
    final fetchError = await guardApiCall(
      () async {
        release = await codePushClientWrapper.getRelease(
          appId: appId,
          releaseVersion: releaseVersion,
        );
        patches = await codePushClientWrapper.getReleasePatches(
          appId: appId,
          releaseId: release.id,
        );
      },
      code: JsonErrorCode.fetchFailed,
      message:
          fetchFailedMessage ??
          'Failed to fetch patches for release "$releaseVersion".',
    );
    if (fetchError != null) {
      return (release: null, patches: <ReleasePatch>[], errorCode: fetchError);
    }
    return (release: release, patches: patches, errorCode: null);
  }

  /// Finds patch [patchNumber] among [patches] of release [releaseVersion].
  ///
  /// When there is no such patch, reports it as a usage error and returns its
  /// exit code: that the release has no patches at all, or else which patch
  /// numbers it does have.
  ({ReleasePatch? patch, int? errorCode}) findPatchOrReport({
    required List<ReleasePatch> patches,
    required int patchNumber,
    required String releaseVersion,
  }) {
    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    if (patch != null) return (patch: patch, errorCode: null);

    if (patches.isEmpty) {
      final errorCode = reportError(
        message: 'No patches found for release "$releaseVersion".',
      );
      return (patch: null, errorCode: errorCode);
    }

    final available = patches.map((p) => p.number).join(', ');
    final errorCode = reportError(
      message:
          'No patch found with number $patchNumber '
          'for release "$releaseVersion".',
      hint: 'Available patches: $available.',
    );
    return (patch: null, errorCode: errorCode);
  }
}
