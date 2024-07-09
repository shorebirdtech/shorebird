import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// {@template promote_patch_command}
/// Promotes a patch to the production channel.
/// {@endtemplate}
class PromotePatchCommand extends ShorebirdCommand {
  /// {@macro promote_patch_command}
  PromotePatchCommand() {
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
      );
  }

  @override
  String get name => 'promote-patch';

  @override
  String get description => 'Promotes a patch to the "stable" channel.';

  @override
  Future<int> run() async {
    final releaseVersion = results['release-version'] as String;
    final patchNumber = int.parse(results['patch-number'] as String);
    final flavor = results.findOption('flavor', argParser: argParser);
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

    final release = await codePushClientWrapper.getRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    final patches = await codePushClientWrapper.getReleasePatches(
      appId: appId,
      releaseId: release.id,
    );
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

    if (patchToPromote.channel == DeploymentTrack.production.channel) {
      logger.err(
        'Patch ${patchToPromote.number} is already in the production channel',
      );
      return ExitCode.usage.code;
    }

    final channel = await codePushClientWrapper.maybeGetChannel(
      appId: appId,
      name: DeploymentTrack.production.channel,
    );
    if (channel == null) {
      // This is a symptom that something bigger is wrong. Apps should always
      // have a production channel.
      logger.err('No production channel found for app $appId');
      return ExitCode.software.code;
    }

    await codePushClientWrapper.promotePatch(
      appId: appId,
      patchId: patchToPromote.id,
      channel: channel,
    );

    return ExitCode.success.code;
  }
}
