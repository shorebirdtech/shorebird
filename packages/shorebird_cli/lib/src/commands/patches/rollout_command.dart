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
import 'package:shorebird_cli/src/rollout_schedule.dart';
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
            'to every device on the track. Required unless '
            '--$rolloutStepsArgName is given.',
        // `--rollout` is the name on `patch` and `promote`, so it works here
        // too.
        aliases: const [rolloutArgName],
        valueHelp: 'percentage',
      )
      ..addOption(
        rolloutStepsArgName,
        help: rolloutStepsHelp("the patch's rollout"),
        valueHelp: 'steps',
      )
      ..addFlag(
        pauseWeekendsArgName,
        help: pauseWeekendsHelp,
        negatable: false,
      )
      ..addOption(
        timezoneArgName,
        help: timezoneHelp,
        valueHelp: 'name',
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
      '--$rolloutStepsArgName instead hands the rollout to a timed schedule '
      'the server advances on its own, as '
      '--$rolloutStepsArgName=$rolloutStepsExample.\n\n'
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

    final (:schedule, error: scheduleError) = readRolloutSchedule(
      results,
      percentageArgName: _percentageArgName,
    );
    if (scheduleError != null) return reportError(message: scheduleError);

    double? percentage;
    if (results[_percentageArgName] case final String value) {
      final (percentage: parsed, :error) = parseRolloutPercentage(
        value,
        argName: _percentageArgName,
      );
      if (parsed == null) return reportError(message: error!);
      percentage = parsed;
    }

    final double targetPercentage;
    if (percentage != null) {
      targetPercentage = percentage;
    } else if (schedule != null) {
      // A schedule's first step is where the rollout lands now; the server
      // raises it from there.
      targetPercentage = schedule.initialPercentage;
    } else {
      return reportError(
        message:
            'Option --$_percentageArgName is mandatory unless '
            '--$rolloutStepsArgName is given.',
        hint:
            'Raise the rollout to a percentage with '
            '--$_percentageArgName=50, or put it on a schedule with '
            '--$rolloutStepsArgName=$rolloutStepsExample.',
      );
    }

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

    final targetLabel = schedule == null
        ? ' to ${formatRolloutPercentage(targetPercentage)}'
        : ' on that schedule';
    final chosen = choosePlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      verb: 'roll out',
      confirmSuffix: targetLabel,
      // Ask only once the checks below pass.
      confirm: false,
    );
    if (chosen.errorCode case final errorCode?) return errorCode;
    final targets = chosen.patches;
    final several = patch.platforms.length > 1;
    final platformsLabel = several
        ? ' (${targets.map(PatchNumber.platformName).join(', ')})'
        : '';

    // The server raises each patch's rollout on its own track, so patches on
    // different tracks would each be raised on a different one.
    final channels = targets.map((p) => p.channel).toSet();
    if (channels.length > 1) {
      final onTrack = targets.firstWhereOrNull((p) => p.channel != null);
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: [
          for (final p in targets)
            if (p.channel == onTrack?.channel) ?p.resolvedPlatform,
        ],
        extraArgs: _rolloutArguments(percentage, schedule),
        reason:
            "Patch $patchNumber's platforms are on different tracks, so "
            'pass --${PatchLookup.platformsArgName} to choose which to roll '
            'out.',
      );
    }

    final channel = channels.single;
    if (channel == null) {
      final appIdArg = results[CommonArguments.appIdArg.name] as String?;
      final flavorArg = results[CommonArguments.flavorArg.name] as String?;
      final promoteCommand = [
        'shorebird patches promote',
        '--release-version $releaseVersion',
        '--patch-number $patchNumber',
        if (appIdArg != null) '--app-id $appIdArg',
        if (flavorArg != null) '--flavor $flavorArg',
        if (schedule == null)
          '--$rolloutArgName ${formatRolloutArgument(targetPercentage)}'
        else
          ...rolloutScheduleArguments(schedule),
        if (chosen.platforms case final platforms?)
          '--${PatchLookup.platformsArgName} ${_platformValues(platforms)}',
      ].join(' ');
      return reportError(
        message:
            'Patch $patchNumber on release $releaseVersion is on no '
            'track$platformsLabel, so it has no rollout to raise.',
        hint: schedule == null
            ? 'Put it on a track at a percentage with: $promoteCommand'
            : 'Put it on a track on that schedule with: $promoteCommand',
      );
    }

    // Raising one platform and then failing on another would leave them
    // apart, so a rollout the server would refuse as lower stops here.
    if (percentage case final percentage? when several) {
      final higher = targets
          .where((p) => (p.rolloutPercentage ?? 100) > percentage)
          .toList();
      if (higher.isNotEmpty) {
        return reportError(
          message:
              'Patch $patchNumber on release $releaseVersion is already '
              'rolling out further than '
              '${formatRolloutPercentage(percentage)} on $channel for '
              '${higher.map(PatchNumber.platformName).join(', ')}, and a '
              'rollout can only be raised.',
          hint:
              'To raise the others, pass --${PatchLookup.platformsArgName} '
              'with only them.',
        );
      }
    }

    if (chosen.platforms == null) {
      confirmAllPlatforms(
        patch: patch,
        releaseVersion: releaseVersion,
        verb: 'roll out',
        confirmSuffix: targetLabel,
      );
    }

    // The server checks the percentage against the current one: the read
    // above can go stale, and it answers 409 when the new one is lower.
    for (final target in targets) {
      final rolloutError = await guardApiCall(
        () => codePushClientWrapper.setPatchRollout(
          appId: appId,
          releaseId: fetched.release!.id,
          patchId: target.id,
          patchNumber: target.number,
          rolloutPercentage: percentage,
          rolloutSchedule: schedule,
        ),
        code: JsonErrorCode.softwareError,
        message:
            'Failed to set the rollout of patch $patchNumber '
            '${several ? '(${PatchNumber.platformName(target)}) ' : ''}'
            'of release "$releaseVersion".',
      );
      if (rolloutError != null) return rolloutError;
    }

    // A schedule always changes the rollout, since the server starts raising
    // it from the first step even when the patch is already there.
    final changed =
        schedule != null ||
        targets.any((p) => targetPercentage != p.rolloutPercentage);
    final updatedPatches = [
      for (final p in targets)
        p
            .copyWith(channel: channel, rolloutPercentage: targetPercentage)
            .withRolloutSchedule(
              steps: schedule?.steps,
              // Only the server knows when the next step applies.
              nextStepAt: null,
              pauseWeekends: schedule?.pauseWeekends,
              timezone: schedule?.timezone,
            ),
    ];
    final updatedPatch = updatedPatches.first;

    if (isJsonMode) {
      emitJsonSuccess({
        'app_id': appId,
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': name,
        'changed': changed,
        'rollout_percentage': targetPercentage,
        if (schedule != null) ...{
          'rollout_steps': [for (final step in schedule.steps) step.toJson()],
          'rollout_pause_weekends': schedule.pauseWeekends,
          'rollout_timezone': ?schedule.timezone,
        },
        'patch': updatedPatch.toJson(),
        'patches': [for (final p in updatedPatches) p.toJson()],
      });
      return ExitCode.success.code;
    }

    logger.success(
      switch (schedule) {
        final schedule? =>
          'Patch $patchNumber on release $releaseVersion is now rolling out '
              'on $channel$platformsLabel on a schedule: '
              '${formatRolloutSchedule(schedule)}.',
        _ when changed =>
          'Patch $patchNumber on release $releaseVersion is now rolling out '
              'to ${formatRolloutPercentage(targetPercentage)} of devices on '
              '$channel$platformsLabel.',
        _ =>
          'Patch $patchNumber on release $releaseVersion is already rolling '
              'out to ${formatRolloutPercentage(targetPercentage)} of devices '
              'on $channel$platformsLabel.',
      },
    );
    if (targetPercentage < 100) logger.info(rolloutOlderDevicesNote);
    for (final p in updatedPatches) {
      if (several) logger.info('${PatchNumber.platformName(p)}:');
      formatPatchDetails(p).forEach(logger.info);
    }
    return ExitCode.success.code;
  }

  /// The arguments that ask for this run's rollout again.
  List<String> _rolloutArguments(
    double? percentage,
    RolloutSchedule? schedule,
  ) => [
    if (percentage != null)
      '--$_percentageArgName=${formatRolloutArgument(percentage)}',
    if (schedule != null) ...rolloutScheduleArguments(schedule),
  ];

  String _platformValues(List<ReleasePlatform> platforms) =>
      platforms.map((p) => p.value).join(',');
}
