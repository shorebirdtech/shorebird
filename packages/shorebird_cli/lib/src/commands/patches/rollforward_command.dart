import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template rollforward_command}
/// Rolls forward (reactivates) a previously rolled-back patch on a release.
/// The server flips `is_rolled_back` from `true` to `false` on the same
/// patch row, so the same patch artifact (same hash, same number) becomes
/// active again. Devices on this release will pick the patch back up on
/// their next launch's auto-update cycle.
///
/// Sample usage:
/// ```sh
/// shorebird patches rollforward --release-version=1.0.0+1 --patch-number=1
/// ```
/// {@endtemplate}
class RollforwardCommand extends ShorebirdCommand {
  /// {@macro rollforward_command}
  RollforwardCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The patch number to roll forward (e.g. "1").',
        mandatory: true,
      )
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to use (e.g. "prod").',
      );
  }

  @override
  String get name => 'rollforward';

  @override
  String get description =>
      'Rolls forward (reactivates) a previously rolled-back patch.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 has been rolled forward.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird patches rollforward --release-version 1.0.0+1 '
        '--patch-number 1 --app-id <id> --json',
      )}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

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
          message: 'Failed to fetch patches for release "$releaseVersion".',
        );
        return e.exitCode;
      }
      rethrow;
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

    if (!patch.isRolledBack) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: 'Patch $patchNumber is already active (not rolled back).',
        );
        return ExitCode.usage.code;
      }
      logger.err('Patch $patchNumber is already active (not rolled back)');
      return ExitCode.usage.code;
    }

    try {
      await codePushClientWrapper.rollforwardPatch(
        appId: appId,
        releaseId: release.id,
        patchId: patch.id,
        patchNumber: patch.number,
      );
    } on ProcessExit catch (e) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.softwareError,
          message:
              'Failed to roll forward patch $patchNumber '
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
        'action': 'rollforward',
      });
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion has been rolled forward.',
    );
    return ExitCode.success.code;
  }
}
