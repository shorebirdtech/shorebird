import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patch_rollback_state_command.dart';

/// {@template rollback_command}
/// Rolls back a patch on a release. Devices on this release that next call
/// the patch-check endpoint will receive the patch number in
/// `rolled_back_patch_numbers`, prompting them to revert to the prior patch
/// (or the base release if no other patch is available on the channel).
///
/// Sample usage:
/// ```sh
/// shorebird patches rollback --release-version=1.0.0+1 --patch-number=1
/// ```
/// {@endtemplate}
class RollbackCommand extends PatchRollbackStateCommand {
  /// {@macro rollback_command}
  RollbackCommand();

  @override
  String get name => 'rollback';

  @override
  bool get targetIsRolledBack => true;

  @override
  String get verb => 'roll back';

  @override
  String get pastParticiple => 'rolled back';

  @override
  String get descriptionLead => 'Rolls back a patch on a release.';

  @override
  String get requireChangeHelp =>
      'Exit with a non-zero status if the patch is already rolled back. '
      'Without this flag, an already rolled-back patch is reported and '
      'exits successfully.';

  @override
  String alreadyInStateMessage(int patchNumber) =>
      'Patch $patchNumber is already rolled back';

  @override
  Future<bool> changePatchState({
    required String appId,
    required int releaseId,
    required int patchId,
    required int patchNumber,
  }) => codePushClientWrapper.rollbackPatch(
    appId: appId,
    releaseId: releaseId,
    patchId: patchId,
    patchNumber: patchNumber,
  );
}
