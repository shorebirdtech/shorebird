import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
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
      );
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

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;

    final (:patch, errorCode: lookupError) = findPatchOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber!,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    // Promoting again would start the rollout over, so a different
    // percentage for a patch already on the track is a job for
    // `patches rollout`.
    if (patch.channel == targetChannel &&
        rolloutPercentage != null &&
        rolloutPercentage != (patch.rolloutPercentage ?? 100)) {
      return reportError(
        message:
            'Patch $patchNumber on release $releaseVersion is already in '
            'channel ${formatPatchTrack(patch)}, and promoting it again would '
            'restart its rollout.',
        hint:
            'To change its rollout, run: ${raiseRolloutCommand(
              releaseVersion: releaseVersion,
              patchNumber: patchNumber,
              percentage: rolloutPercentage,
              appId: results[CommonArguments.appIdArg.name] as String?,
              flavor: results[CommonArguments.flavorArg.name] as String?,
            )}',
      );
    }

    // Already on the requested track (at the requested percentage, if one was
    // given): nothing to do, which is success, as it is for rollback and
    // rollforward.
    if (patch.channel == targetChannel) {
      if (isJsonMode) {
        emitJsonSuccess(
          _successJson(
            appId: appId,
            releaseVersion: releaseVersion,
            patch: patch,
            track: targetChannel,
            changed: false,
          ),
        );
        return ExitCode.success.code;
      }
      logger.info(
        'Patch $patchNumber on release $releaseVersion is already in channel '
        '${formatPatchTrack(patch)}.',
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
    final promoteError = await guardApiCall(
      () => codePushClientWrapper.promotePatch(
        appId: appId,
        patchId: patch.id,
        channel: trackChannel,
        rolloutPercentage: rolloutPercentage,
      ),
      code: JsonErrorCode.softwareError,
      message:
          'Failed to set track for patch $patchNumber '
          'of release "$releaseVersion".',
    );
    if (promoteError != null) return promoteError;

    // Promoting starts a new rollout on the track.
    final promotedPatch = patch.copyWith(
      channel: targetChannel,
      rolloutPercentage: rolloutPercentage ?? 100,
    );

    if (isJsonMode) {
      emitJsonSuccess(
        _successJson(
          appId: appId,
          releaseVersion: releaseVersion,
          patch: promotedPatch,
          track: targetChannel,
          changed: true,
        ),
      );
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion is now in channel '
      '${formatPatchTrack(promotedPatch)}!',
    );
    if (rolloutPercentage != null && rolloutPercentage < 100) {
      logger.info(rolloutOlderDevicesNote);
    }

    return ExitCode.success.code;
  }

  Map<String, Object?> _successJson({
    required String appId,
    required String releaseVersion,
    required ReleasePatch patch,
    required String track,
    required bool changed,
  }) => {
    'app_id': appId,
    'release_version': releaseVersion,
    'patch_number': patch.number,
    'track': track,
    'changed': changed,
    'patch': patch.toJson(),
  };
}
