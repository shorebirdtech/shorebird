import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

/// {@template login_command}
///
/// `shorebird login`
/// Login as a new Shorebird user.
/// {@endtemplate}
class LoginCommand extends ShorebirdCommand {
  /// {@macro login_command}
  LoginCommand({required super.logger, super.auth});

  @override
  String get description => 'Login as a new Shorebird user.';

  @override
  String get name => 'login';

  @override
  Future<int> run() async {
    final credentials = auth.credentials;
    if (credentials != null) {
      logger
        ..info('You are already logged in.')
        ..info("Run 'shorebird logout' to log out and try again.");
      return ExitCode.success.code;
    }

    try {
      await auth.login(prompt);
      logger.info('''

🎉 ${lightGreen.wrap('Welcome to Shorebird! You are now logged in.')}

🔑 Credentials are stored in ${lightCyan.wrap(auth.credentialsFilePath)}.
🚪 To logout use: "${lightCyan.wrap('shorebird logout')}".''');
      return ExitCode.success.code;
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }
  }

  void prompt(String url) {
    logger.info('''
The Shorebird CLI needs your authorization to manage apps, releases, and patches on your behalf.

In a browser, visit this URL to log in:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
  }
}
