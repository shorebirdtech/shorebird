import 'package:mason_logger/mason_logger.dart';
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

  static final forceHelpText = '''
${styleBold.wrap('Deprecated')}
'''
      'If your app has known safe native code or asset changes, you can use '
      'the ${cyan.wrap('--allow-native-diffs')} or '
      '${cyan.wrap('--allow-asset-diffs')} flags instead. We do not recommend '
      'using these flags unless you are '
      '${styleBold.wrap('absolutely')} sure that the changes are safe.';

  static final allowNativeDiffsHelpText = '''
Patch even if native code diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Native code changes cannot be included in a patch and attempting to do so can cause your app to crash or behave unexpectedly.''';

  static final allowAssetDiffsHelpText = '''
Patch even if asset diffs are detected.
NOTE: this is ${styleBold.wrap('not')} recommended. Asset changes cannot be included in a patch can cause your app to behave unexpectedly.''';

  static const forceDeprecationErrorMessage =
      'The --force flag has been deprecated';

  static final forceDeprecationExplanation =
      'If your app has known safe native code or asset changes, you can use '
      'the ${cyan.wrap('--allow-native-diffs')} or '
      '${cyan.wrap('--allow-asset-diffs')} '
      'flags. We do not recommend using these flags unless you are '
      '${styleBold.wrap('absolutely sure')} that the changes are safe. '
      'Note: the ${cyan.wrap('--force flag')} is not required for use in CI '
      'environments.';

  @override
  String get description =>
      'Manage patches for a specific release in Shorebird.';

  @override
  String get name => 'patch';
}
