import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template release_command}
/// `shorebird release`
/// Create new app releases.
/// {@endtemplate}
class ReleaseCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseCommand() {
    addSubcommand(ReleaseAarCommand());
    addSubcommand(ReleaseAndroidCommand());
    addSubcommand(ReleaseIosCommand());
    addSubcommand(ReleaseIosFrameworkCommand());
  }

  @override
  String get description => 'Manage your Shorebird app releases.';

  @override
  String get name => 'release';

  static const forceHelpText = 'The force flag has been deprecated';

  static const forceDeprecationErrorMessage =
      'The --force flag has been deprecated';

  static final forceDeprecationExplanation = '''
If you believe you have a valid reason to use the --force flag, please reach out to the Shorebird team by filing an issue at ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/new'))}

Note: the --force flag is not required for use in CI environments.''';
}
