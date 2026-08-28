import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
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
class RollbackCommand extends ShorebirdCommand with PatchNumberArgument {
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
      )
      ..addFlag(
        'require-change',
        help:
            'Exit with a non-zero status if the patch is already rolled back. '
            'Without this flag, an already rolled-back patch is reported and '
            'exits successfully.',
        negatable: false,
      );
  }

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Rolls back a patch on a release.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 has been rolled back.\n'
      '  ID:          42\n'
      '  Number:      1\n'
      '  Track:       stable\n'
      '  Rolled back: yes\n\n'
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
    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumber == null) return patchNumberError!;

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

    // Only the POST can say whether the patch changed: the read above can go
    // stale, and the server answers 304 when there was nothing to do.
    final bool changed;
    try {
      changed = await codePushClientWrapper.rollbackPatch(
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

    if (!changed && results['require-change'] as bool) {
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

    final rolledBackPatch = patch.copyWith(isRolledBack: true);

    if (isJsonMode) {
      emitJsonSuccess({
        'release_version': releaseVersion,
        'patch_number': patchNumber,
        'action': 'rollback',
        'changed': changed,
        'patch': rolledBackPatch.toJson(),
      });
      return ExitCode.success.code;
    }

    if (changed) {
      logger.success(
        'Patch $patchNumber on release $releaseVersion has been rolled back.',
      );
    } else {
      logger.info('Patch $patchNumber is already rolled back');
    }
    _logPatch(rolledBackPatch);
    return ExitCode.success.code;
  }

  void _logPatch(ReleasePatch patch) =>
      formatPatchDetails(patch).forEach(logger.info);
}
