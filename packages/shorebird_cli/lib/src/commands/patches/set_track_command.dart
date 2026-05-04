import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template set_track_command}
/// Sets the track of a patch.
///
/// Sample usage:
/// ```sh
/// shorebird patches set-track --release-version=1.0.0+1 --patch-number=1 --track=beta
/// ```
///
/// {@endtemplate}
class SetTrackCommand extends ShorebirdCommand {
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
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to use when building the app.',
      );
  }

  @override
  String get name => 'set-track';

  @override
  String get description =>
      'Sets the track of a patch.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 is now in channel stable!\n\n'
      '${ShorebirdCommand.jsonHint('shorebird patches set-track --release 1.0.0+1 --patch 1 --track stable --app-id <id> --json')}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion = results['release'] as String;
    final patchNumber = int.parse(results['patch'] as String);
    final targetChannel = results['track'] as String;

    if (targetChannel.isEmpty ||
        targetChannel.length > CommonArguments.trackNameMaxLength) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message:
              'Track name must be between 1 and '
              '${CommonArguments.trackNameMaxLength} characters.',
        );
        return ExitCode.usage.code;
      }
      logger.err(
        'Track name must be between 1 and '
        '${CommonArguments.trackNameMaxLength} characters.',
      );
      return ExitCode.usage.code;
    }

    final Release release;
    final List<ReleasePatch> patches;
    try {
      release = await codePushClientWrapper.getRelease(
        appId: appId,
        releaseVersion: releaseVersion,
      );
      patches = await codePushClientWrapper.getReleasePatches(
        appId: appId,
        releaseId: release.id,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.fetchFailed,
          message: 'Failed to fetch patches for release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (patches.isEmpty) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: 'No patches found for release "$releaseVersion".',
        );
        return ExitCode.usage.code;
      }
      logger.err('No patches found for release $releaseVersion');
      return ExitCode.usage.code;
    }

    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    if (patch == null) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message:
              'No patch found with number $patchNumber '
              'for release "$releaseVersion".',
        );
        return ExitCode.usage.code;
      }
      logger
        ..err('No patch found with number $patchNumber')
        ..info(
          'Available patches: ${patches.map((p) => p.number).join(', ')}',
        );
      return ExitCode.usage.code;
    }

    if (patch.channel == targetChannel) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: 'Patch $patchNumber is already in channel "$targetChannel".',
        );
        return ExitCode.usage.code;
      }
      logger.err(
        'Patch ${patch.number} is already in channel $targetChannel',
      );
      return ExitCode.usage.code;
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

    try {
      await codePushClientWrapper.promotePatch(
        appId: appId,
        patchId: patch.id,
        channel: channel,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message:
              'Failed to set track for patch $patchNumber '
              'of release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    if (isJsonMode) {
      emitJsonSuccess({
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'track': targetChannel,
      });
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion is now in channel $targetChannel!',
    );

    return ExitCode.success.code;
  }
}
