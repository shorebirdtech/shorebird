import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template patch_rollback_state_command}
/// Shared implementation of `shorebird patches rollback` and
/// `shorebird patches rollforward`, which set a patch's rolled-back state to
/// [targetIsRolledBack] and differ only in wording and the API call.
/// {@endtemplate}
abstract class PatchRollbackStateCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument, PatchLookup {
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

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;

    final (:patch, errorCode: lookupError) = findPatchOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    // Only the POST can say whether the patch changed: the read above can go
    // stale, and the server answers 304 when there was nothing to do.
    late final bool changed;
    final changeError = await guardApiCall(
      () async => changed = await changePatchState(
        appId: appId,
        releaseId: fetched.release!.id,
        patchId: patch.id,
        patchNumber: patch.number,
      ),
      code: JsonErrorCode.softwareError,
      message:
          'Failed to $verb patch $patchNumber of release "$releaseVersion".',
    );
    if (changeError != null) return changeError;

    if (!changed && results['require-change'] as bool) {
      return reportError(message: alreadyInStateMessage(patchNumber));
    }

    final updatedPatch = patch.copyWith(isRolledBack: targetIsRolledBack);

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
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
}
