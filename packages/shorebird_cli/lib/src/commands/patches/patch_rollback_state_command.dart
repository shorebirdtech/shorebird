import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/release_patch.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

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
        CommonArguments.patchNumberArg.name,
        help: 'The patch number to $verb (e.g. "1").',
        mandatory: true,
      );
    addPlatformsOption(action: verb);
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

  /// Asks the server to change the state of the patches under [patchId]'s
  /// number, only [platforms]' when given. Returns whether any changed.
  @protected
  Future<bool> changePatchState({
    required String appId,
    required int releaseId,
    required int patchId,
    required int patchNumber,
    List<ReleasePlatform>? platforms,
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

    final (:patch, errorCode: lookupError) = findPatchNumberOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    // Without --platforms the server rolls forward every platform's patch,
    // and only when they are all rolled back or all active.
    final rolledBackStates = patch.patches.map((p) => p.isRolledBack).toSet();
    if (!targetIsRolledBack &&
        requestedPlatforms == null &&
        rolledBackStates.length > 1) {
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: _notInTargetState(patch),
        reason:
            "Some of patch $patchNumber's platforms are rolled back and some "
            'are not, so pass --${PatchLookup.platformsArgName} to choose '
            'which to $verb.',
      );
    }

    final chosen = choosePlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      verb: verb,
    );
    if (chosen.errorCode case final errorCode?) return errorCode;

    // Only the POST can say whether the patch changed: the read above can go
    // stale, and the server answers 304 when there was nothing to do.
    late final bool changed;
    // Caught inside the guarded call, which would otherwise report the
    // server's message for older clients in --json mode.
    var platformsDiffer = false;
    final changeError = await guardApiCall(
      () async {
        try {
          changed = await changePatchState(
            appId: appId,
            releaseId: fetched.release!.id,
            patchId: chosen.patches.first.id,
            patchNumber: patch.number,
            platforms: chosen.platforms,
          );
        } on ApiErrorExit catch (e) {
          if (!isPlatformsDiffer(e)) rethrow;
          platformsDiffer = true;
        }
      },
      code: JsonErrorCode.softwareError,
      message:
          'Failed to $verb patch $patchNumber of release "$releaseVersion".',
    );
    if (platformsDiffer) {
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: _notInTargetState(patch),
      );
    }
    if (changeError != null) return changeError;

    if (!changed && results['require-change'] as bool) {
      return reportError(message: alreadyInStateMessage(patchNumber));
    }

    final updatedPatches = [
      for (final p in chosen.patches)
        p.copyWith(isRolledBack: targetIsRolledBack),
    ];
    final updatedPatch = updatedPatches.first;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': name,
        'changed': changed,
        'patch': updatedPatch.toJson(),
        'patches': [for (final p in updatedPatches) p.toJson()],
      });
      return ExitCode.success.code;
    }

    final several = patch.platforms.length > 1;
    final platformsLabel = several
        ? ' (${updatedPatches.map(PatchNumber.platformName).join(', ')})'
        : '';
    if (changed) {
      logger.success(
        'Patch $patchNumber on release $releaseVersion '
        'has been $pastParticiple$platformsLabel.',
      );
    } else {
      logger.info(alreadyInStateMessage(patchNumber));
    }
    for (final p in updatedPatches) {
      if (several) logger.info('${PatchNumber.platformName(p)}:');
      formatPatchDetails(p).forEach(several ? _indented : logger.info);
    }
    return ExitCode.success.code;
  }

  void _indented(String line) => logger.info('  $line');

  /// The platforms under [patch] whose patch is not yet in the target state.
  List<ReleasePlatform> _notInTargetState(PatchNumber patch) => [
    for (final p in patch.patches)
      if (p.isRolledBack != targetIsRolledBack) ?p.resolvedPlatform,
  ];
}
