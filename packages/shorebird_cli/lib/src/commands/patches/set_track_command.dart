import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/extensions/release_patch.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_cli/src/rollout_schedule.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

const _jsonExample =
    'shorebird patches set-track --release-version 1.0.0+1 --patch-number 1 '
    '--track stable --app-id <id> --json';

/// {@template set_track_command}
/// Sets the track of a patch.
///
/// Sample usage:
/// ```sh
/// shorebird patches set-track --release-version=1.0.0+1 --patch-number=1 \
///   --track=beta
/// ```
///
/// {@endtemplate}
class SetTrackCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument, PatchLookup {
  /// {@macro set_track_command}
  ///
  /// When [defaultTrack] is set, `--track` is optional and defaults to it.
  SetTrackCommand({String? defaultTrack}) {
    argParser
      // `--release` and `--patch` were this command's original names; kept as
      // hidden aliases so existing scripts keep working.
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        aliases: const ['release'],
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        CommonArguments.patchNumberArg.name,
        aliases: const ['patch'],
        help: 'The patch number to set the track for (e.g. "1").',
        mandatory: true,
      )
      // Agents and older docs call tracks channels, so --channel works too.
      ..addOption(
        'track',
        aliases: const ['channel'],
        help:
            'The deployment track to move the patch to '
            '("stable", "beta", "staging", or any custom track name '
            'up to ${CommonArguments.trackNameMaxLength} characters).',
        mandatory: defaultTrack == null,
        defaultsTo: defaultTrack,
      )
      ..addOption(
        rolloutArgName,
        help: rolloutHelp('the patch'),
        valueHelp: 'percentage',
      )
      ..addOption(
        rolloutStepsArgName,
        help: rolloutStepsHelp('the patch'),
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
    addPlatformsOption(action: 'move');
    addAppScopeOptions();
  }

  @override
  String get name => 'set-track';

  @override
  String get description =>
      'Sets the track of a patch.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 is now in channel stable!\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumberError != null) return patchNumberError;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final targetChannel = results['track'] as String;

    final nameError = CommonArguments.nameError(
      label: 'Track name',
      value: targetChannel,
      maxLength: CommonArguments.trackNameMaxLength,
    );
    if (nameError != null) return reportError(message: nameError);

    double? rolloutPercentage;
    if (results[rolloutArgName] case final String rollout) {
      final (:percentage, :error) = parseRolloutPercentage(
        rollout,
        argName: rolloutArgName,
      );
      if (error != null) return reportError(message: error);
      rolloutPercentage = percentage;
    }

    final (:schedule, error: scheduleError) = readRolloutSchedule(
      results,
      percentageArgName: rolloutArgName,
    );
    if (scheduleError != null) return reportError(message: scheduleError);
    // A schedule starts the rollout at its first step, so that is where the
    // patch lands either way.
    final requestedPercentage =
        rolloutPercentage ?? schedule?.initialPercentage;

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;

    final (:patch, errorCode: lookupError) = findPatchNumberOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber!,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    // Without --platforms the server moves every platform's patch, and only
    // when they are all on one track.
    if (requestedPlatforms == null && patch.tracksDiffer) {
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: _notOn(patch, targetChannel),
        extraArgs: ['--track=$targetChannel'],
        reason:
            "Patch $patchNumber's platforms are on different tracks, so "
            'pass --${PatchLookup.platformsArgName} to choose which to move.',
      );
    }

    final chosen = choosePlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      verb: 'move',
      confirmSuffix: ' to $targetChannel',
    );
    if (chosen.errorCode case final errorCode?) return errorCode;
    final targets = chosen.patches;
    final several = patch.platforms.length > 1;
    String platformsLabel(List<ReleasePatch> patches) =>
        several ? ' (${patches.map(PatchNumber.platformName).join(', ')})' : '';

    // A schedule is never a no-op: promoting again would restart the rollout,
    // so a patch already on the track goes through `patches rollout`.
    final onTrackForSchedule = schedule == null
        ? null
        : targets.firstWhereOrNull((p) => p.channel == targetChannel);
    if (onTrackForSchedule case final onTrack?) {
      return reportError(
        message:
            'Patch $patchNumber on release $releaseVersion is already in '
            'channel ${formatPatchTrack(onTrack)}, and promoting it again '
            'would restart its rollout.',
        hint:
            'To put its rollout on that schedule, run: '
            '${scheduleRolloutCommand(
              releaseVersion: releaseVersion,
              patchNumber: patchNumber,
              schedule: schedule!,
              appId: results[CommonArguments.appIdArg.name] as String?,
              flavor: results[CommonArguments.flavorArg.name] as String?,
            )}',
      );
    }

    // Promoting again would start the rollout over, so a different
    // percentage for a patch already on the track is a job for
    // `patches rollout`.
    final onTrackAtOtherRollout = requestedPercentage == null
        ? null
        : targets.firstWhereOrNull(
            (p) =>
                p.channel == targetChannel &&
                requestedPercentage != (p.rolloutPercentage ?? 100),
          );
    if (onTrackAtOtherRollout case final onTrack?) {
      final current = onTrack.rolloutPercentage ?? 100;
      if (requestedPercentage! < current) {
        return reportError(
          message:
              'Patch $patchNumber on release $releaseVersion is already '
              'rolling out to ${formatRolloutPercentage(current)} of devices '
              'on $targetChannel, and a rollout can only be raised.',
          hint:
              'To stop new devices getting it, leave its rollout where it is; '
              'to take it off devices, roll it back with `shorebird patches '
              'rollback`.',
        );
      }
      return reportError(
        message:
            'Patch $patchNumber on release $releaseVersion is already in '
            'channel ${formatPatchTrack(onTrack)}, and promoting it again '
            'would restart its rollout.',
        hint:
            'To change its rollout, run: ${raiseRolloutCommand(
              releaseVersion: releaseVersion,
              patchNumber: patchNumber,
              percentage: requestedPercentage,
              appId: results[CommonArguments.appIdArg.name] as String?,
              flavor: results[CommonArguments.flavorArg.name] as String?,
            )}',
      );
    }

    // Promoting a patch already on the track would restart its rollout, so
    // only the others move.
    final toMove = [
      for (final p in targets)
        if (p.channel != targetChannel) p,
    ];
    final alreadyThere = [
      for (final p in targets)
        if (p.channel == targetChannel) p,
    ];

    // Already on the requested track (at the requested percentage, if one was
    // given): nothing to do, which is success, as it is for rollback and
    // rollforward.
    if (toMove.isEmpty) {
      if (isJsonMode) {
        emitJsonSuccess(
          _successJson(
            appId: appId,
            releaseVersion: releaseVersion,
            patches: targets,
            track: targetChannel,
            changed: false,
          ),
        );
        return ExitCode.success.code;
      }
      logger.info(
        'Patch $patchNumber on release $releaseVersion is already in channel '
        '${formatPatchTrack(targets.first)}${platformsLabel(targets)}.',
      );
      return ExitCode.success.code;
    }

    var channel = await codePushClientWrapper.maybeGetChannel(
      appId: appId,
      name: targetChannel,
    );
    if (channel == null) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.interactivePromptRequired,
          message: 'Channel "$targetChannel" does not exist.',
          hint:
              'Create it by publishing a patch with --track=$targetChannel, '
              'or run without --json to create it interactively.',
        );
        return ExitCode.usage.code;
      }
      final shouldCreate = logger.confirm(
        'No channel named ${lightCyan.wrap(targetChannel)} found. '
        'Do you want to create it?',
        hint:
            'Pass --track=<existing-channel> to use an existing channel. '
            'Channels are auto-created when a patch is published with '
            '--track=<name>; set-track itself has no flag to skip this '
            'confirmation.',
      );
      if (!shouldCreate) {
        logger.err('Aborting.');
        throw PromptDeclinedExit();
      }

      channel = await codePushClientWrapper.createChannel(
        appId: appId,
        name: targetChannel,
      );
    }

    // Non-null here; bind it so the closure below keeps the promotion.
    final trackChannel = channel;
    final int? promoteError;
    try {
      promoteError = await guardApiCall(
        () => codePushClientWrapper.promotePatch(
          appId: appId,
          patchId: toMove.first.id,
          channel: trackChannel,
          rolloutPercentage: rolloutPercentage,
          rolloutSchedule: schedule,
          platforms: alreadyThere.isEmpty
              ? chosen.platforms
              : [for (final p in toMove) ?p.resolvedPlatform],
        ),
        code: JsonErrorCode.softwareError,
        message:
            'Failed to set track for patch $patchNumber '
            'of release "$releaseVersion".',
      );
    } on ApiErrorExit catch (e) {
      if (!isPlatformsDiffer(e)) rethrow;
      return reportPlatformsDiffer(
        patch: patch,
        releaseVersion: releaseVersion,
        suggested: _notOn(patch, targetChannel),
        extraArgs: ['--track=$targetChannel'],
      );
    }
    if (promoteError != null) return promoteError;

    // Promoting starts a new rollout on the track.
    final promotedPatches = [
      for (final p in toMove)
        p
            .copyWith(
              channel: targetChannel,
              rolloutPercentage: requestedPercentage ?? 100,
            )
            .withRolloutSchedule(
              steps: schedule?.steps,
              // Only the server knows when the next step applies.
              nextStepAt: null,
              pauseWeekends: schedule?.pauseWeekends,
              timezone: schedule?.timezone,
            ),
    ];

    if (isJsonMode) {
      emitJsonSuccess(
        _successJson(
          appId: appId,
          releaseVersion: releaseVersion,
          patches: [
            for (final p in targets)
              promotedPatches.firstWhereOrNull((m) => m.id == p.id) ?? p,
          ],
          track: targetChannel,
          changed: true,
        ),
      );
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion is now in channel '
      '${formatPatchTrack(promotedPatches.first)}'
      '${platformsLabel(promotedPatches)}!',
    );
    for (final p in alreadyThere) {
      logger.info(
        '${PatchNumber.platformName(p)} stays in channel '
        '${formatPatchTrack(p)}.',
      );
    }
    if (schedule != null) {
      logger.info(
        'Its rollout rises on a schedule: ${formatRolloutSchedule(schedule)}.',
      );
    }
    if (requestedPercentage != null && requestedPercentage < 100) {
      logger.info(rolloutOlderDevicesNote);
    }

    return ExitCode.success.code;
  }

  /// The platforms under [patch] whose patch is not on [channel].
  List<ReleasePlatform> _notOn(PatchNumber patch, String channel) => [
    for (final p in patch.patches)
      if (p.channel != channel) ?p.resolvedPlatform,
  ];

  Map<String, Object?> _successJson({
    required String appId,
    required String releaseVersion,
    required List<ReleasePatch> patches,
    required String track,
    required bool changed,
  }) => {
    'app_id': appId,
    'release_version': releaseVersion,
    'patch_number': patches.first.number,
    'track': track,
    'changed': changed,
    'patch': patches.first.toJson(),
    'patches': [for (final p in patches) p.toJson()],
  };
}
