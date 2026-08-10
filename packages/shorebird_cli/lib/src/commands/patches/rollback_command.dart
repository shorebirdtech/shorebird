import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template rollback_command}
/// Rolls back a patch on a release. Devices on this release that next call
/// the patch-check endpoint will receive the patch number in
/// `rolled_back_patch_numbers`, prompting them to revert to the prior patch
/// (or the base release if no other patch is available on the channel).
///
/// Sample usage:
/// ```sh
/// shorebird patches rollback --release-version=1.0.0+1 --patch-number=1
/// ```
/// {@endtemplate}
class RollbackCommand extends ShorebirdCommand {
  /// {@macro rollback_command}
  RollbackCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        'patch-number',
        help: 'The patch number to roll back (e.g. "1").',
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
  String get name => 'rollback';

  @override
  String get description =>
      'Rolls back a patch on a release.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 has been rolled back.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird patches rollback --release-version 1.0.0+1 '
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

    if (patch.isRolledBack) {
      if (isJsonMode) {
        emitJsonError(
          code: JsonErrorCode.usageError,
          message: 'Patch $patchNumber is already rolled back.',
        );
        return ExitCode.usage.code;
      }
      logger.err('Patch $patchNumber is already rolled back');
      return ExitCode.usage.code;
    }

    try {
      await codePushClientWrapper.rollbackPatch(
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
              'Failed to roll back patch $patchNumber '
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
        'action': 'rollback',
      });
      return ExitCode.success.code;
    }

    logger.success(
      'Patch $patchNumber on release $releaseVersion has been rolled back.',
    );
    return ExitCode.success.code;
  }
}
