import 'package:googleapis_auth/auth_io.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart'
    as api;

/// {@template login_ci_command}
/// `shorebird login:ci`
/// Login as a CI user.
/// {@endtemplate}
class LoginCiCommand extends ShorebirdCommand {
  LoginCiCommand() {
    argParser.addOption(
      'provider',
      abbr: 'p',
      allowed: api.AuthProvider.values.map((e) => e.name),
      defaultsTo: api.AuthProvider.google.name,
      help: 'The authentication provider to use. Defaults to Google.',
    );
  }

  @override
  String get description => 'Login as a CI user.';

  @override
  String get name => 'login:ci';

  @override
  Future<int> run() async {
    final api.AuthProvider provider;
    if (results.wasParsed('provider')) {
      provider = api.AuthProvider.values.byName(results['provider'] as String);
    } else {
      provider = logger.chooseOne(
        'Choose an auth provider',
        choices: api.AuthProvider.values,
        display: (p) => p.displayName,
      );
    }

    final AccessCredentials credentials;
    try {
      credentials = await auth.loginCI(provider, prompt: prompt);
    } on UserNotFoundException catch (error) {
      logger
        ..err(
          '''
We could not find a Shorebird account for ${error.email}.''',
        )
        ..info(
          '''If you have not yet created an account, go to "${link(uri: Uri.parse('https://console.shorebird.dev'))}" to create one. If you believe this is an error, please reach out to us via Discord, we're happy to help!''',
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
  
${lightCyan.wrap('export $shorebirdTokenEnvVar="\$SHOREBIRD_TOKEN" $shorebirdTokenProviderEnvVar="${provider.name}" && shorebird patch android')}
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
