import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template set_track_command}
/// Sets the channel of a patch.
///
/// Sample usage:
/// ```sh
/// shorebird patches set-track --release=1.0.0 --patch=1 --track=beta
/// ```
///
/// {@endtemplate
class SetTrackCommand extends ShorebirdCommand {
  /// {@macro set_track_command}
  SetTrackCommand() {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'release',
        help: 'The release version that the patch belongs to (ex: "1.0.0")',
        mandatory: true,
      )
      ..addOption(
        'patch',
        help: 'The patch number to set the channel for (ex: "1")',
        mandatory: true,
      )
      ..addOption(
        'track',
        help: 'The channel to set the patch to',
        mandatory: true,
      );
  }

  @override
  String get name => 'set-track';

  @override
  String get description => 'Sets the track of a patch';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final releaseVersion = results['release'] as String;
    final patchNumber = int.parse(results['patch'] as String);
    final flavor = results.findOption('flavor', argParser: argParser);
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);
    final targetChannel = results['track'] as String;

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    final patches = await codePushClientWrapper.getReleasePatches(
      appId: appId,
      releaseId: release.id,
    );
    if (patches.isEmpty) {
      logger.err('No patches found for release $releaseVersion');
      return ExitCode.usage.code;
    }

    final patchToPromote = patches.firstWhereOrNull(
      (patch) => patch.number == patchNumber,
    );
    if (patchToPromote == null) {
      logger
        ..err('No patch found with number $patchNumber')
        ..info(
          '''Available patches: ${patches.map((patch) => patch.number).join(', ')}''',
        );

      return ExitCode.usage.code;
    }

    var channel = await codePushClientWrapper.maybeGetChannel(
      appId: appId,
      name: targetChannel,
    );
    if (channel == null) {
      final shouldCreateChannel = logger.confirm(
        '''No channel named ${lightCyan.wrap(targetChannel)} found. Do you want to create it?''',
      );
      if (!shouldCreateChannel) {
        return ExitCode.success.code;
      }

      channel = await codePushClientWrapper.createChannel(
        appId: appId,
        name: targetChannel,
      );
    }

    if (patchToPromote.channel == targetChannel) {
      logger.err(
        'Patch ${patchToPromote.number} is already in channel $targetChannel',
      );
      return ExitCode.usage.code;
    }

    await codePushClientWrapper.promotePatch(
      appId: appId,
      patchId: patchToPromote.id,
      channel: channel,
    );

    logger.success(
      '''Patch ${patchToPromote.number} on release $releaseVersion is now in channel $targetChannel!''',
    );

    return ExitCode.success.code;
  }
}
