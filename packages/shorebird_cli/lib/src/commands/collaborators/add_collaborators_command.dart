import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template add_collaborators_command}
/// `shorebird collaborators add`
/// Add a new collaborator to a Shorebird app.
/// {@endtemplate}
class AddCollaboratorsCommand extends ShorebirdCommand {
  /// {@macro add_collaborators_command}
  AddCollaboratorsCommand({super.buildCodePushClient}) {
    argParser
      ..addOption(
        _appIdOption,
        help: 'The app id to add a collaborator to.',
      )
      ..addOption(
        _collaboratorEmailOption,
        help: 'The email of the collaborator to add.',
      );
  }

  static const String _appIdOption = 'app-id';
  static const String _collaboratorEmailOption = 'email';

  @override
  String get description => 'Add a new collaborator to a Shorebird app.';

  @override
  String get name => 'add';

  @override
  Future<int>? run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: ShorebirdEnvironment.hostedUri,
    );

    final appId = results[_appIdOption] as String? ??
        ShorebirdEnvironment.getShorebirdYaml()?.appId;
    if (appId == null) {
      logger.err(
        '''
Could not find an app id.
You must either specify an app id via the "--$_appIdOption" flag or run this command from within a directory with a valid "shorebird.yaml" file.''',
      );
      return ExitCode.usage.code;
    }

    final collaborator = results[_collaboratorEmailOption] as String? ??
        logger.prompt(
          '''${lightGreen.wrap('?')} What is the email of the collaborator you would like to add?''',
        );

    logger.info(
      '''
${styleBold.wrap(lightGreen.wrap('🚀 Ready to add a new collaborator!'))}
📱 App ID: ${lightCyan.wrap(appId)}
🤝 Collaborator: ${lightCyan.wrap(collaborator)}
''',
    );

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Adding collaborator');
    try {
      await client.createCollaborator(appId: appId, email: collaborator);
      progress.complete();
    } catch (error) {
      progress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ New Collaborator Added!');

    return ExitCode.success.code;
  }
}
