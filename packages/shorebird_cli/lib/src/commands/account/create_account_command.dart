import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template create_account_command}
/// `shorebird account create`
/// Create a new Shorebird account.
/// {@endtemplate}
class CreateAccountCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro create_account_command}
  CreateAccountCommand({required super.logger, super.auth});

  @override
  String get description => 'Create a new Shorebird account.';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    final User newUser;
    try {
      newUser = await auth.signUp(
        authPrompt: authPrompt,
        namePrompt: namePrompt,
      );
    } on UserAlreadyLoggedInException catch (error) {
      logger
        ..info('You are already logged in as <${error.email}>.')
        ..info("Run ${lightCyan.wrap('shorebird logout')} to log out and try again.");
      return ExitCode.success.code;
    } on UserAlreadyExistsException catch (error) {
      // TODO(bryanoltman): change this message based on the user's subscription
      // status.
      logger.info('''
You already have an account, ${error.user.displayName}!
To subscribe, run ${lightCyan.wrap('shorebird account subscribe')}.
''');
      return ExitCode.success.code;
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

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

  void authPrompt(String url) {
    logger.info('''
Shorebird currently requires a Google account for authentication. If you'd like to use a different kind of auth, please let us know: ${lightCyan.wrap('https://github.com/shorebirdtech/shorebird/issues/335')}.

Follow the link below to authenticate:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
  }

  String namePrompt() => logger.prompt('''
Tell us your name to finish creating your account:''');
}
