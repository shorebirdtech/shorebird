import 'package:googleapis_auth/auth_io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';

/// {@template login_ci_command}
/// `shorebird login:ci`
/// Login as a CI user.
/// {@endtemplate}
class LoginCICommand extends ShorebirdCommand {
  @override
  String get description => 'Login as a CI user.';

  @override
  String get name => 'login:ci';

  @override
  Future<int> run() async {
    final AccessCredentials credentials;

    try {
      credentials = await auth.loginCI(prompt);
    } on UserNotFoundException catch (error) {
      logger
        ..err(
          '''
We could not find a Shorebird account for ${error.email}.''',
        )
        ..info(
          """If you have not yet created an account, you can do so by running "${lightCyan.wrap('shorebird account create')}". If you believe this is an error, please reach out to us via Discord, we're happy to help!""",
        );
      return ExitCode.software.code;
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    logger.info('''

🎉 ${lightGreen.wrap('Success! Use the following token to login on a CI server:')}

${lightCyan.wrap(credentials.refreshToken)}

Example:
  
${lightCyan.wrap(r'EXPORT SHOREBIRD_TOKEN="$SHOREBIRD_TOKEN" shorebird patch android')}
''');
    return ExitCode.success.code;
  }

  void prompt(String url) {
    logger.info('''
The Shorebird CLI needs your authorization to manage apps, releases, and patches on your behalf.

In a browser, visit this URL to log in:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
  }
}
