import 'dart:async';

import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template delete_collaborators_command}
/// `shorebird collaborators delete`
/// Delete an existing collaborator from a Shorebird app.
/// {@endtemplate}
class DeleteCollaboratorsCommand extends ShorebirdCommand {
  /// {@macro delete_collaborators_command}
  DeleteCollaboratorsCommand({super.buildCodePushClient}) {
    argParser
      ..addOption(
        _appIdOption,
        help: 'The app id that contains the collaborator to be deleted.',
      )
      ..addOption(
        _collaboratorEmailOption,
        help: 'The email of the collaborator to delete.',
      );
  }

  static const String _appIdOption = 'app-id';
  static const String _collaboratorEmailOption = 'email';

  @override
  String get description =>
      'Delete an existing collaborator from a Shorebird app.';

  @override
  String get name => 'delete';

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

    final email = results[_collaboratorEmailOption] as String? ??
        logger.prompt(
          '''${lightGreen.wrap('?')} What is the email of the collaborator you would like to delete?''',
        );

    final getCollaboratorsProgress = logger.progress('Fetching collaborators');
    final List<Collaborator> collaborators;
    try {
      collaborators = await client.getCollaborators(appId: appId);
      getCollaboratorsProgress.complete();
    } catch (error) {
      getCollaboratorsProgress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    final collaborator = collaborators.firstWhereOrNull(
      (c) => c.email == email,
    );
    if (collaborator == null) {
      logger.err(
        '''
Could not find a collaborator with the email "$email".
Available collaborators:
${collaborators.map((c) => '  - ${c.email}').join('\n')}''',
      );
      return ExitCode.software.code;
    }

    logger.info(
      '''
${styleBold.wrap(lightGreen.wrap('🗑️  Ready to delete an existing collaborator!'))}
📱 App ID: ${lightCyan.wrap(appId)}
🤝 Collaborator: ${lightCyan.wrap(collaborator.email)}
''',
    );

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborted.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Deleting collaborator');
    try {
      await client.deleteCollaborator(
        appId: appId,
        userId: collaborator.userId,
      );
      progress.complete();
    } catch (error) {
      progress.fail();
      logger.err('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ Collaborator Deleted!');

    return ExitCode.success.code;
  }
}
