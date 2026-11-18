import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/release_patch.dart';
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
    addPlatformsOption(action: 'roll out further');
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
      'When patches for several platforms share the patch number, this '
      'raises each of them, or only those --platforms names.\n\n'
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

    final (:patch, errorCode: lookupError) = findPatchNumberOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    final several = patch.platforms.length > 1;
    final percentageArg =
        '--$_percentageArgName=${formatRolloutArgument(percentage)}';

    // The server raises one patch at a time, so without --platforms this
    // raises every platform's patch, and only when they are all on one
    // track.
    if (requestedPlatforms == null && patch.tracksDiffer) {
      final firstTrack = patch.patches
          .firstWhereOrNull((p) => p.channel != null)
          ?.channel;
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: [
          for (final p in patch.patches)
            if (p.channel == firstTrack) ?p.resolvedPlatform,
        ],
        extraArgs: [percentageArg],
        reason:
            "Patch $patchNumber's platforms are on different tracks, so "
            'pass --${PatchLookup.platformsArgName} to choose which to roll '
            'out further.',
      );
    }

    // Checked before asking which platforms to raise, so the question is
    // never asked for a rollout that cannot happen.
    final candidates = switch (requestedPlatforms) {
      null => patch.patches,
      final platforms => [for (final p in platforms) ?patch.patchFor(p)],
    };
    final offTrack = candidates.where((p) => p.channel == null).toList();
    if (offTrack.isNotEmpty) {
      final appIdArg = results[CommonArguments.appIdArg.name] as String?;
      final flavorArg = results[CommonArguments.flavorArg.name] as String?;
      final offTrackValues = offTrack
          .map((p) => p.resolvedPlatform?.value)
          .nonNulls
          .join(',');
      final promoteCommand = [
        'shorebird patches promote',
        '--release-version $releaseVersion',
        '--patch-number $patchNumber',
        if (appIdArg != null) '--app-id $appIdArg',
        if (flavorArg != null) '--flavor $flavorArg',
        if (several) '--${PatchLookup.platformsArgName} $offTrackValues',
        '--rollout ${formatRolloutArgument(percentage)}',
      ].join(' ');
      final String message;
      if (!several) {
        message =
            'Patch $patchNumber on release $releaseVersion is on no track, so '
            'it has no rollout to raise.';
      } else {
        final names = offTrack.map(PatchNumber.platformName).join(' and ');
        message = offTrack.length == 1
            ? "Patch $patchNumber's $names patch on release $releaseVersion "
                  'is on no track, so it has no rollout to raise.'
            : "Patch $patchNumber's $names patches on release "
                  '$releaseVersion are on no track, so they have no rollout '
                  'to raise.';
      }
      return reportError(
        message: message,
        hint:
            'Put ${offTrack.length == 1 ? 'it' : 'them'} on a track at a '
            'percentage with: $promoteCommand',
      );
    }

    final chosen = choosePlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      verb: 'roll out',
      confirmSuffix: ' to ${formatRolloutPercentage(percentage)}',
    );
    if (chosen.errorCode case final errorCode?) return errorCode;
    final targets = chosen.patches;
    final platformsLabel = several
        ? ' (${targets.map(PatchNumber.platformName).join(', ')})'
        : '';

    // With one patch the server's answer is enough. With several, a patch
    // already above the percentage would fail after the ones before it were
    // raised, so it is refused before any of them changes.
    if (targets.length > 1) {
      final above = targets.firstWhereOrNull(
        (p) => (p.rolloutPercentage ?? 100) > percentage,
      );
      if (above != null) {
        return reportError(
          message:
              "Patch $patchNumber's ${PatchNumber.platformName(above)} patch "
              'on release $releaseVersion is already rolling out to '
              '${formatRolloutPercentage(above.rolloutPercentage ?? 100)} of '
              'devices on ${above.channel}, and a rollout can only be raised.',
          hint:
              'To raise the others, pass --${PatchLookup.platformsArgName} '
              'without ${above.resolvedPlatform?.value}.',
        );
      }
    }

    final raised = <ReleasePatch>[];
    for (final target in targets) {
      final label = several ? ' (${PatchNumber.platformName(target)})' : '';
      final alreadyRaised = raised.isEmpty
          ? ''
          : ' after raising ${raised.map(PatchNumber.platformName).join(', ')} '
                'to ${formatRolloutPercentage(percentage)}';
      final int? rolloutError;
      try {
        // The server checks the percentage against the current one: the
        // read above can go stale, and it answers 409 when the new one is
        // lower.
        rolloutError = await guardApiCall(
          () => codePushClientWrapper.setPatchRollout(
            appId: appId,
            releaseId: fetched.release!.id,
            patchId: target.id,
            patchNumber: target.number,
            rolloutPercentage: percentage,
          ),
          code: JsonErrorCode.softwareError,
          message:
              'Failed to set the rollout of patch $patchNumber$label of '
              'release "$releaseVersion"$alreadyRaised.',
        );
      } on Object {
        _warnPartlyRaised(raised, target, percentage);
        rethrow;
      }
      if (rolloutError != null) {
        _warnPartlyRaised(raised, target, percentage);
        return rolloutError;
      }
      raised.add(target);
    }

    final changed = targets.any((p) => p.rolloutPercentage != percentage);
    final updatedPatches = [
      for (final p in targets) p.copyWith(rolloutPercentage: percentage),
    ];
    final channel = targets.first.channel;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': name,
        'changed': changed,
        'rollout_percentage': percentage,
        'patch': updatedPatches.first.toJson(),
        'patches': [for (final p in updatedPatches) p.toJson()],
      });
      return ExitCode.success.code;
    }

    logger.success(
      changed
          ? 'Patch $patchNumber on release $releaseVersion is now rolling out '
                'to ${formatRolloutPercentage(percentage)} of devices on '
                '$channel$platformsLabel.'
          : 'Patch $patchNumber on release $releaseVersion is already rolling '
                'out to ${formatRolloutPercentage(percentage)} of devices on '
                '$channel$platformsLabel.',
    );
    if (percentage < 100) logger.info(rolloutOlderDevicesNote);
    for (final p in updatedPatches) {
      if (several) logger.info('${PatchNumber.platformName(p)}:');
      for (final line in formatPatchDetails(p)) {
        logger.info(several ? '  $line' : line);
      }
    }
    return ExitCode.success.code;
  }

  /// Says which of the patches before [failed] were raised to [percentage],
  /// when there were any, so a failure part way is not read as no change.
  void _warnPartlyRaised(
    List<ReleasePatch> raised,
    ReleasePatch failed,
    double percentage,
  ) {
    if (raised.isEmpty || isJsonMode) return;
    logger.warn(
      'The rollout of patch ${failed.number} was raised to '
      '${formatRolloutPercentage(percentage)} for '
      '${raised.map(PatchNumber.platformName).join(', ')}, but not for '
      '${PatchNumber.platformName(failed)} or any platform after it.',
    );
  }
}
