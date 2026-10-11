import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

const _jsonExample =
    'shorebird patches set-track --release 1.0.0+1 --patch 1 '
    '--track stable --app-id <id> --json';

/// {@template set_track_command}
/// Sets the track of a patch.
///
/// Sample usage:
/// ```sh
/// shorebird patches set-track --release=1.0.0+1 --patch=1 --track=beta
/// ```
///
/// {@endtemplate}
class SetTrackCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument, PatchLookup {
  /// {@macro set_track_command}
  SetTrackCommand() {
    argParser
      ..addOption(
        'release',
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch',
        help: 'The patch number to set the track for (e.g. "1").',
        mandatory: true,
      )
      ..addOption(
        'track',
        help:
            'The deployment track to move the patch to '
            '("stable", "beta", "staging", or any custom track name '
            'up to ${CommonArguments.trackNameMaxLength} characters).',
        mandatory: true,
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

    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber(
      option: 'patch',
    );
    if (patchNumberError != null) return patchNumberError;

    final releaseVersion = results['release'] as String;
    final targetChannel = results['track'] as String;

    if (targetChannel.isEmpty ||
        targetChannel.length > CommonArguments.trackNameMaxLength) {
      return reportError(
        message:
            'Track name must be between 1 and '
            '${CommonArguments.trackNameMaxLength} characters.',
      );
    }

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;
    final patches = fetched.patches;

    if (patches.isEmpty) {
      return reportError(
        message: 'No patches found for release $releaseVersion',
        jsonMessage: 'No patches found for release "$releaseVersion".',
      );
    }

    final (:patch, errorCode: lookupError) = findPatchOrReport(
      patches: patches,
      patchNumber: patchNumber!,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    // Already on the requested track: nothing to do, which is success, as it
    // is for rollback and rollforward.
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
        '$targetChannel.',
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
        return ExitCode.success.code;
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
      ),
      code: JsonErrorCode.softwareError,
      message:
          'Failed to set track for patch $patchNumber '
          'of release "$releaseVersion".',
    );
    if (promoteError != null) return promoteError;

    if (isJsonMode) {
      emitJsonSuccess(
        _successJson(
          appId: appId,
          releaseVersion: releaseVersion,
          patch: patch.copyWith(channel: targetChannel),
          track: targetChannel,
          changed: true,
        ),
      );
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion is now in channel '
      '$targetChannel!',
    );

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
