import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template create_account_command}
/// `shorebird account create`
/// Create a new Shorebird account.
/// {@endtemplate}
class CreateAccountCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro create_account_command}
  CreateAccountCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  });

  @override
  String get description => 'Create a new Shorebird account.';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    if (auth.isAuthenticated) {
      logger
        ..info('You are already logged in as <${auth.email}>.')
        ..info("Run 'shorebird logout' to log out and try again.");
      return ExitCode.success.code;
    }

    try {
      await auth.getCredentials(prompt);
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    try {
      final user = await client.getCurrentUser();
      // TODO(bryanoltman): change this message based on the user's subscription
      // status.
      logger.info('''
You already have an account, ${user.displayName}!
To subscribe, run ${green.wrap('shorebird account subscribe')}.
''');

      return ExitCode.success.code;
    } on UserNotFoundException {
      // Do nothing, it is expected that we don't have a user record for this
      // email address.
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    final name = logger.prompt('''
Tell us your name to finish creating your account:''');

    final progress = logger.progress('Creating account');
    final User newUser;
    try {
      newUser = await client.createUser(name: name);
    } catch (error) {
      auth.logout();
      progress.fail(error.toString());
      return ExitCode.software.code;
    }

    progress.complete(
      lightGreen.wrap('Account created for ${newUser.email}!'),
    );

    logger.info(
      '''

🎉 ${lightGreen.wrap('Welcome to Shorebird, ${newUser.displayName}!')}
🔑 Credentials are stored in ${lightCyan.wrap(auth.credentialsFilePath)}.
🚪 To logout, use: "${lightCyan.wrap('shorebird logout')}".
⬆️  To upgrade your account, use: "${lightCyan.wrap('shorebird account subscribe')}".

Enjoy! Please let us know via Discord if we can help.''',
    );
    return ExitCode.success.code;
  }

  void prompt(String url) {
    logger.info('''
Shorebird currently requires a Google account for authentication. If you'd like to use a different kind of auth, please let us know: ${lightCyan.wrap('https://github.com/shorebirdtech/shorebird/issues/335')}.

Follow the link below to authenticate:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
  }
}
