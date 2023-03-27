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
    final session = auth.currentSession;
    if (session != null) {
      logger
        ..info('You are already logged in.')
        ..info("Run 'shorebird logout' to log out and try again.");
      return ExitCode.success.code;
    }

    final apiKey = logger.prompt(
      '${lightGreen.wrap('?')} Please enter your API Key:',
    );
    final loginProgress = logger.progress('Logging into shorebird.dev');
    try {
      auth.login(apiKey: apiKey);
      loginProgress.complete();
      logger.info('''
${lightGreen.wrap('You are now logged in.')}

🔑 Credentials are stored in ${lightCyan.wrap(auth.sessionFilePath)}.
🚪 To logout use: "${lightCyan.wrap('shorebird logout')}".''');
      return ExitCode.success.code;
    } catch (error) {
      loginProgress.fail();
      logger.err(error.toString());
      return ExitCode.software.code;
    }
  }
}
