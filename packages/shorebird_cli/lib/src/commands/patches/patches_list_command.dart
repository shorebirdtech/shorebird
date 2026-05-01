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

/// {@template patches_list_command}
/// `shorebird patches list`
/// List patches for a release.
/// {@endtemplate}
class PatchesListCommand extends ShorebirdCommand {
  /// {@macro patches_list_command}
  PatchesListCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to list patches for (e.g. "prod").',
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List patches for a release.';

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

    if (isJsonMode) {
      emitJsonSuccess({
        'patches': patches.map((p) => p.toJson()).toList(),
      });
      return ExitCode.success.code;
    }

    if (patches.isEmpty) {
      logger.info('No patches found.');
      return ExitCode.success.code;
    }

    for (final patch in patches) {
      final number = lightCyan.wrap('#${patch.number}');
      final channel = patch.channel != null ? '  track: ${patch.channel}' : '';
      final rolledBack = patch.isRolledBack ? '  [rolled back]' : '';
      logger.info('$number$channel$rolledBack');
    }

    return ExitCode.success.code;
  }
}
