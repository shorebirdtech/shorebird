import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logging/shorebird_logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template set_channel_command}
/// Sets the channel of a patch.
/// {@endtemplate
class SetChannelCommand extends ShorebirdCommand {
  /// {@macro set_channel_command}
  SetChannelCommand() {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'release-version',
        help: 'The release being patched',
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The number of the patch to promote to the stable channel',
        mandatory: true,
      )
      ..addOption(
        'channel',
        help: 'The channel to set the patch to',
        mandatory: true,
      );
  }

  @override
  String get name => 'set-channel';

  @override
  String get description => 'Sets the channel of a patch';

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

    final releaseVersion = results['release-version'] as String;
    final patchNumber = int.parse(results['patch-number'] as String);
    final flavor = results.findOption('flavor', argParser: argParser);
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);
    final targetChannel = results['channel'] as String;

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
      'Patch ${patchToPromote.number} is now in channel $targetChannel!',
    );

    return ExitCode.success.code;
  }
}
