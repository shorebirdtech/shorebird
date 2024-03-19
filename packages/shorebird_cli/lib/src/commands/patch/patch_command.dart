import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template patch_command}
/// `shorebird patch`
/// Create new app release patch.
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand {
  /// {@macro patch_command}
  PatchCommand() {
    addSubcommand(PatchAarCommand());
    addSubcommand(PatchAndroidCommand());
    addSubcommand(PatchIosCommand());
    addSubcommand(PatchIosFrameworkCommand());
  }

  static const forceHelpText = '''
**Deprecated**

If your app has known safe native code or asset changes, you can use the
--allow-native-diffs or --allow-asset-diffs flags instead. We do not recommend
using these flags unless you are *absolutely* sure that the changes are safe.
''';

  static const allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is **not** recommended.''';

  static const allowAssetDiffsHelpText = '''
Patch even if asset diffs are detected.
NOTE: this is **not** recommended.''';

  static const forceDeprecationErrorMessage =
      'The --force flag has been deprecated';

  static const forceDeprecationExplanation = '''
If your app has known safe native code or asset changes, you can use the
--allow-native-diffs or --allow-asset-diffs flags. We do not recommend using
these flags unless you are *absolutely* sure that the changes are safe.

Note: the --force flag is not required for use in CI environments.''';

  @override
  String get description =>
      'Manage patches for a specific release in Shorebird.';

  @override
  String get name => 'patch';
}
