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
      '  Track:       stable\n'
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

    final (:patch, errorCode: lookupError) = findPatchOrReport(
      patches: fetched.patches,
      patchNumber: patchNumber,
      releaseVersion: releaseVersion,
    );
    if (patch == null) return lookupError!;

    if (isJsonMode) {
      emitJsonSuccess({'patch': patch.toJson()});
      return ExitCode.success.code;
    }

    formatPatchDetails(patch).forEach(logger.info);

    return ExitCode.success.code;
  }
}
