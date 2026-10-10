import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_rollback_state_command}
/// Shared implementation of `shorebird patches rollback` and
/// `shorebird patches rollforward`, which set a patch's rolled-back state to
/// [targetIsRolledBack] and differ only in wording and the API call.
/// {@endtemplate}
abstract class PatchRollbackStateCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument {
  /// {@macro patch_rollback_state_command}
  PatchRollbackStateCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The patch number to $verb (e.g. "1").',
        mandatory: true,
      );
    addAppScopeOptions();
    argParser.addFlag(
      'require-change',
      help: requireChangeHelp,
      negatable: false,
    );
  }

  /// The rolled-back state this command puts the patch in.
  @protected
  bool get targetIsRolledBack;

  /// The verb, as in "roll back" or "roll forward".
  @protected
  String get verb;

  /// The past participle, as in "rolled back" or "rolled forward".
  @protected
  String get pastParticiple;

  /// The first line of [description].
  @protected
  String get descriptionLead;

  /// Help for the `--require-change` flag.
  @protected
  String get requireChangeHelp;

  /// Reported when the patch was already in the target state.
  @protected
  String alreadyInStateMessage(int patchNumber);

  /// Asks the server to change the patch's state. Returns whether it changed.
  @protected
  Future<bool> changePatchState({
    required String appId,
    required int releaseId,
    required int patchId,
    required int patchNumber,
  });

  @override
  String get description =>
      '$descriptionLead\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 has been $pastParticiple.\n'
      '  ID:          42\n'
      '  Number:      1\n'
      '  Track:       stable\n'
      '  Rolled back: ${targetIsRolledBack ? 'yes' : 'no'}\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird patches $name --release-version 1.0.0+1 '
        '--patch-number 1 --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumber == null) return patchNumberError!;

    final lookup = await _findPatch(
      appId: appId,
      releaseVersion: releaseVersion,
      patchNumber: patchNumber,
    );
    final (:release, :patch, errorCode: lookupError) = lookup;
    if (lookupError != null) return lookupError;

    // Only the POST can say whether the patch changed: the read above can go
    // stale, and the server answers 304 when there was nothing to do.
    final bool changed;
    try {
      changed = await changePatchState(
        appId: appId,
        releaseId: release!.id,
        patchId: patch!.id,
        patchNumber: patch.number,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message:
              'Failed to $verb patch $patchNumber '
              'of release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (!changed && results['require-change'] as bool) {
      final message = alreadyInStateMessage(patchNumber);
      return reportError(message: message, jsonMessage: '$message.');
    }

    final updatedPatch = patch.copyWith(isRolledBack: targetIsRolledBack);

    if (isJsonMode) {
      emitJsonSuccess({
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': name,
        'changed': changed,
        'patch': updatedPatch.toJson(),
      });
      return ExitCode.success.code;
    }

    if (changed) {
      logger.success(
        'Patch $patchNumber on release $releaseVersion '
        'has been $pastParticiple.',
      );
    } else {
      logger.info(alreadyInStateMessage(patchNumber));
    }
    formatPatchDetails(updatedPatch).forEach(logger.info);
    return ExitCode.success.code;
  }

  /// Fetches [releaseVersion] and finds patch [patchNumber] on it, reporting
  /// the failure and returning an exit code when either is missing.
  Future<({Release? release, ReleasePatch? patch, int? errorCode})> _findPatch({
    required String appId,
    required String releaseVersion,
    required int patchNumber,
  }) async {
    final Release release;
    final List<ReleasePatch> patches;
    try {
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
      patches = await codePushClientWrapper.getReleasePatches(
        appId: appId,
        releaseId: release.id,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch patches for release "$releaseVersion".',
        );
        return (release: null, patch: null, errorCode: e.exitCode);
      }
      rethrow;
    }

    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    if (patch == null) {
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
      return (release: release, patch: null, errorCode: ExitCode.usage.code);
    }
    return (release: release, patch: patch, errorCode: null);
  }
}
