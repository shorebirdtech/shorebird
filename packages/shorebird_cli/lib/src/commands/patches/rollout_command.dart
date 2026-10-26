import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

const _percentageArgName = 'percentage';

const _jsonExample =
    'shorebird patches rollout --release-version 1.0.0+1 --patch-number 1 '
    '--percentage 50 --app-id <id> --json';

/// {@template rollout_command}
/// Raises the share of its track's devices that a patch is offered to.
///
/// Sample usage:
/// ```sh
/// shorebird patches rollout --release-version=1.0.0+1 --patch-number=1 \
///   --percentage=50
/// ```
/// {@endtemplate}
class RolloutCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument, PatchLookup {
  /// {@macro rollout_command}
  RolloutCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        CommonArguments.patchNumberArg.name,
        help: 'The patch number to roll out further (e.g. "1").',
        mandatory: true,
      )
      ..addOption(
        _percentageArgName,
        help:
            "The percentage of the track's devices to offer the patch to, "
            'a number greater than 0 and at most 100 with at most two '
            'decimal places (e.g. "50"). Rollouts only go up; 100 offers it '
            'to every device on the track.',
        // `--rollout` is the name on `patch` and `promote`, so it works here
        // too.
        aliases: const [rolloutArgName],
        valueHelp: 'percentage',
        mandatory: true,
      );
    addAppScopeOptions();
  }

  @override
  String get name => 'rollout';

  @override
  String get description =>
      "Raises the percentage of its track's devices a patch is offered to.\n\n"
      'A patch put on a track with --rollout (on `shorebird patch` or '
      '`shorebird patches promote`) reaches that share of the devices on it. '
      'This raises the share; it cannot lower it. To stop a rollout, leave '
      'it where it is or run `shorebird patches rollback`.\n\n'
      '$rolloutOlderDevicesNote\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 is now rolling out to 50% of devices on '
      'stable.\n'
      '  ID:          42\n'
      '  Number:      1\n'
      '  Track:       stable (50%)\n'
      '  Rolled back: no\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumber == null) return patchNumberError!;

    final (:percentage, error: percentageError) = parseRolloutPercentage(
      results[_percentageArgName] as String,
      argName: _percentageArgName,
    );
    if (percentage == null) return reportError(message: percentageError!);

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

    final channel = patch.channel;
    if (channel == null) {
      final appIdArg = results[CommonArguments.appIdArg.name] as String?;
      final flavorArg = results[CommonArguments.flavorArg.name] as String?;
      final promoteCommand = [
        'shorebird patches promote',
        '--release-version $releaseVersion',
        '--patch-number $patchNumber',
        if (appIdArg != null) '--app-id $appIdArg',
        if (flavorArg != null) '--flavor $flavorArg',
        '--rollout ${formatRolloutArgument(percentage)}',
      ].join(' ');
      return reportError(
        message:
            'Patch $patchNumber on release $releaseVersion is on no track, so '
            'it has no rollout to raise.',
        hint:
            'Put it on a track at a percentage with: '
            '$promoteCommand',
      );
    }

    // The server checks the percentage against the current one: the read
    // above can go stale, and it answers 409 when the new one is lower.
    final rolloutError = await guardApiCall(
      () => codePushClientWrapper.setPatchRollout(
        appId: appId,
        releaseId: fetched.release!.id,
        patchId: patch.id,
        patchNumber: patch.number,
        rolloutPercentage: percentage,
      ),
      code: JsonErrorCode.softwareError,
      message:
          'Failed to set the rollout of patch $patchNumber of release '
          '"$releaseVersion".',
    );
    if (rolloutError != null) return rolloutError;

    final changed = percentage != patch.rolloutPercentage;
    final updatedPatch = patch.copyWith(
      channel: channel,
      rolloutPercentage: percentage,
    );

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': name,
        'changed': changed,
        'rollout_percentage': percentage,
        'patch': updatedPatch.toJson(),
      });
      return ExitCode.success.code;
    }

    logger.success(
      changed
          ? 'Patch $patchNumber on release $releaseVersion is now rolling out '
                'to ${formatRolloutPercentage(percentage)} of devices on '
                '$channel.'
          : 'Patch $patchNumber on release $releaseVersion is already rolling '
                'out to ${formatRolloutPercentage(percentage)} of devices on '
                '$channel.',
    );
    if (percentage < 100) logger.info(rolloutOlderDevicesNote);
    formatPatchDetails(updatedPatch).forEach(logger.info);
    return ExitCode.success.code;
  }
}
