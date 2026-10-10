import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patch_rollback_state_command.dart';

/// {@template rollforward_command}
/// Rolls forward (reactivates) a previously rolled-back patch on a release.
/// The server flips `is_rolled_back` from `true` to `false` on the same
/// patch row, so the same patch artifact (same hash, same number) becomes
/// active again. Devices on this release will pick the patch back up on
/// their next launch's auto-update cycle.
///
/// Sample usage:
/// ```sh
/// shorebird patches rollforward --release-version=1.0.0+1 --patch-number=1
/// ```
/// {@endtemplate}
class RollforwardCommand extends PatchRollbackStateCommand {
  /// {@macro rollforward_command}
  RollforwardCommand();

  @override
  String get name => 'rollforward';

  @override
  bool get targetIsRolledBack => false;

  @override
  String get verb => 'roll forward';

  @override
  String get pastParticiple => 'rolled forward';

  @override
  String get descriptionLead =>
      'Rolls forward (reactivates) a previously rolled-back patch.';

  @override
  String get requireChangeHelp =>
      'Exit with a non-zero status if the patch is already active. '
      'Without this flag, an already active patch is reported and '
      'exits successfully.';

  @override
  String alreadyInStateMessage(int patchNumber) =>
      'Patch $patchNumber is already active (not rolled back)';

  @override
  Future<bool> changePatchState({
    required String appId,
    required int releaseId,
    required int patchId,
    required int patchNumber,
  }) => codePushClientWrapper.rollforwardPatch(
    appId: appId,
    releaseId: releaseId,
    patchId: patchId,
    patchNumber: patchNumber,
  );
}
