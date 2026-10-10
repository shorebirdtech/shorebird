import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/commands/patches/patch_lookup.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

const _jsonExample =
    'shorebird patches list --release-version 1.0.0+1 --app-id '
    '<id> --json';

/// {@template patches_list_command}
/// `shorebird patches list`
/// List patches for a release.
/// {@endtemplate}
class PatchesListCommand extends ShorebirdCommand
    with AppScopedCommand, PatchLookup {
  /// {@macro patches_list_command}
  PatchesListCommand() {
    argParser.addOption(
      CommonArguments.releaseVersionArg.name,
      help: CommonArguments.patchReleaseVersionDescription,
      mandatory: true,
    );
    addAppScopeOptions();
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      'List patches for a release.\n\n'
      'Example output (one line per patch):\n'
      '  42  #1  track: stable\n'
      '  43  #2  [no track]\n'
      '  44  #3  track: beta  [rolled back]\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    final releaseVersion =
        results[CommonArguments.releaseVersionArg.name] as String;

    final fetched = await fetchReleasePatches(
      appId: appId,
      releaseVersion: releaseVersion,
    );
    if (fetched.errorCode case final errorCode?) return errorCode;
    final patches = fetched.patches;

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
      final id = patch.id;
      final number = lightCyan.wrap('#${patch.number}');
      final channel = patch.channel != null
          ? '  track: ${patch.channel}'
          : '  [no track]';
      final rolledBack = patch.isRolledBack ? '  [rolled back]' : '';
      logger.info('$id  $number$channel$rolledBack');
    }

    return ExitCode.success.code;
  }
}
