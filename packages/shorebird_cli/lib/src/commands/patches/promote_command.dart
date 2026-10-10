import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template promote_command}
/// Promotes a patch to the production channel.
/// {@endtemplate}
class PromoteCommand extends ShorebirdCommand
    with PatchNumberArgument, PatchLookup {
  /// {@macro promote_command}
  PromoteCommand() {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addOption(
        'release-version',
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The number of the patch to promote to the stable channel.',
        mandatory: true,
      );
  }

  @override
  String get name => 'promote';

  @override
  String get description => 'Promotes a patch to the "stable" channel.';

  @override
  Future<int> run() async {
    // Deprecated commands don't grow new surface area. Refuse --json with
    // a structured envelope that points to the replacement command, instead
    // of leaking a free-form deprecation warning to stdout.
    if (isJsonMode) {
      emitJsonError(
        code: JsonErrorCode.usageError,
        message:
            'shorebird patches promote is deprecated and does not support '
            '--json output.',
        hint: 'Use `shorebird patches set-track --track=stable` instead.',
      );
      return ExitCode.usage.code;
    }

    logger.warn(
      '''This command is deprecated and will be removed in a future release. Use `shorebird patches set-track --track=stable` instead.''',
    );

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumberError != null) return patchNumberError;

    final releaseVersion = results['release-version'] as String;
    final flavor = results.findOption('flavor', argParser: argParser);
    final appId = shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

    // --json is refused above, so today a failed fetch is rethrown rather
    // than reported; the errorCode check keeps this in step with the other
    // patches commands.
    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;

    final (patch: patchToPromote, errorCode: lookupError) = findPatchOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber!,
      releaseVersion: releaseVersion,
    );
    if (patchToPromote == null) return lookupError!;

    if (patchToPromote.channel == DeploymentTrack.stable.channel) {
      logger.err('Patch ${patchToPromote.number} is already live');
      return ExitCode.usage.code;
    }

    final channel = await codePushClientWrapper.maybeGetChannel(
      appId: appId,
      name: DeploymentTrack.stable.channel,
    );
    if (channel == null) {
      // This is a symptom that something bigger is wrong. Apps should always
      // have a production channel.
      logger.err(
        '''
No production channel found for app $appId.
      
This is a bug and should never happen. Please file an issue at https://github.com/shorebirdtech/shorebird/issues/new?assignees=&labels=bug&projects=&template=bug_report.md&title=fix%3A+''',
      );
      return ExitCode.software.code;
    }

    await codePushClientWrapper.promotePatch(
      appId: appId,
      patchId: patchToPromote.id,
      channel: channel,
    );

    logger.success(
      'Patch ${patchToPromote.number} is now live for release $releaseVersion!',
    );

    return ExitCode.success.code;
  }
}
