import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patches_info_command}
/// `shorebird patches info`
/// Show details for a specific patch.
/// {@endtemplate}
class PatchesInfoCommand extends ShorebirdCommand {
  /// {@macro patches_info_command}
  PatchesInfoCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The patch number to show details for (ex: "1").',
        mandatory: true,
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to query patches for (e.g. "prod").',
      );
  }

  @override
  String get name => 'info';

  @override
  String get description => 'Show details for a specific patch.';

  @override
  Future<int> run() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: explicitAppId == null,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final appId =
        explicitAppId ??
        shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final patchNumber = int.parse(results['patch-number'] as String);

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
          message: 'Failed to fetch patch $patchNumber '
              'for release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
    }

    final patch = patches.firstWhereOrNull((p) => p.number == patchNumber);
    if (patch == null) {
      logger
        ..err('No patch found with number $patchNumber.')
        ..info(
          'Available patches: ${patches.map((p) => p.number).join(', ')}',
        );
      return ExitCode.usage.code;
    }

    if (isJsonMode) {
      emitJsonSuccess({'patch': patch.toJson()});
      return ExitCode.success.code;
    }

    logger.info('Number:      ${patch.number}');
    if (patch.channel != null) {
      logger.info('Track:       ${patch.channel}');
    }
    logger.info('Rolled back: ${patch.isRolledBack ? 'yes' : 'no'}');
    if (patch.notes != null) {
      logger.info('Notes:       ${patch.notes}');
    }

    return ExitCode.success.code;
  }
}
