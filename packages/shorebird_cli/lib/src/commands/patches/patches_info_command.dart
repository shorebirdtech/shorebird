import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/commands/patches/patch_number_argument.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

const _jsonExample =
    'shorebird patches info --release-version 1.0.0+1 '
    '--patch-number 1 --app-id <id> --json';

/// {@template patches_info_command}
/// `shorebird patches info`
/// Show details for a specific patch.
/// {@endtemplate}
class PatchesInfoCommand extends ShorebirdCommand
    with AppScopedCommand, PatchNumberArgument, PatchLookup {
  /// {@macro patches_info_command}
  PatchesInfoCommand() {
    argParser
      ..addOption(
        CommonArguments.releaseVersionArg.name,
        help: CommonArguments.patchReleaseVersionDescription,
        mandatory: true,
      )
      ..addOption(
        CommonArguments.patchNumberArg.name,
        help: 'The patch number to show details for (e.g. "1").',
        mandatory: true,
      );
    addPlatformsOption(action: 'show');
    addAppScopeOptions();
  }

  @override
  String get name => 'info';

  @override
  String get description =>
      'Show details for a specific patch.\n\n'
      'Example output:\n'
      '  ID:          42\n'
      '  Number:      1\n'
      '  Track:       stable (10%)\n'
      '  Rolled back: no\n'
      '  Notes:       Optional patch notes.\n'
      '  Artifacts:\n'
      '    android  arm64-v8a    1.20 MB\n'
      '    android  armeabi-v7a  1.10 MB\n'
      '    ios      arm64        896 KB\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;
    final (:patchNumber, errorCode: patchNumberError) = resolvePatchNumber();
    if (patchNumber == null) return patchNumberError!;

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
      fetchFailedMessage:
          'Failed to fetch patch $patchNumber '
          'for release "$releaseVersion".',
    );
    if (fetched.errorCode case final errorCode?) return errorCode;

    final (:patch, errorCode: lookupError) = findPatchNumberOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    final chosen = choosePlatforms(
      patch: patch,
      releaseVersion: releaseVersion,
      verb: 'show',
      confirm: false,
    );
    if (chosen.errorCode case final errorCode?) return errorCode;
    final patches = chosen.patches;

    if (isJsonMode) {
      emitJsonSuccess({
        'patch': patches.first.toJson(),
        'patches': [for (final p in patches) p.toJson()],
      });
      return ExitCode.success.code;
    }

    if (patches.length == 1) {
      formatPatchDetails(patches.single).forEach(logger.info);
      return ExitCode.success.code;
    }
    if (patch.tracksDiffer) {
      logger.info(
        'Patch $patchNumber has patches for several platforms, on different '
        'tracks.',
      );
    }
    for (final p in patches) {
      logger.info('${PatchNumber.platformName(p)}:');
      for (final line in formatPatchDetails(p)) {
        logger.info('  $line');
      }
    }

    return ExitCode.success.code;
  }
}
