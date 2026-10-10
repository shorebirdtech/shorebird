import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/auth/shorebird_oauth.dart';
import 'package:shorebird_cli/src/browser.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template login_command}
/// `shorebird login`
/// Login as a new Shorebird user.
/// {@endtemplate}
class LoginCommand extends ShorebirdCommand {
  /// {@macro login_command}
  LoginCommand() {
    argParser.addFlag(
      deviceFlag,
      negatable: false,
      help:
          'Log in by entering a code in a browser on any device, instead of '
          'opening a browser on this machine. Used automatically over SSH, '
          'on CI, and on Linux without a display.',
    );
  }

  /// The flag that forces the device code login.
  static const deviceFlag = 'device';

  @override
  String get description => 'Login as a new Shorebird user.';

  @override
  String get name => 'login';

  @override
  Future<int> run() async {
    if (auth.isAuthenticated) {
      final progress = logger.progress('Checking existing credentials');
      final bool hasValidCredentials;
      try {
        hasValidCredentials = await auth.hasValidCredentials();
      } on Exception catch (error) {
        // An answer that is not `invalid_grant` says nothing about the stored
        // credentials either, so keep them; but don't blame the network for
        // an answer that arrived.
        if (error is ShorebirdAuthException && error.isRateLimited) {
          progress.fail('Too many requests, try again shortly.');
          logger.detail('$error');
          return ExitCode.tempFail.code;
        }
        if (error is ShorebirdAuthException && _isClientError(error)) {
          progress.fail(
            'The Shorebird auth service refused to check your credentials '
            '(${_describeRefusal(error)}).',
          );
          logger
            ..detail('$error')
            ..info(
              'If this keeps happening, run '
              '${lightCyan.wrap('shorebird logout')} and then '
              '${lightCyan.wrap('shorebird login')}.',
            );
          return ExitCode.tempFail.code;
        }
        // The auth service could not answer, which says nothing about the
        // stored credentials. Discarding them here would log a user out for
        // running this off wifi.
        progress.fail('Could not reach the Shorebird auth service.');
        logger
          ..err('$error')
          ..info('Check your network connection and try again.');
        return ExitCode.tempFail.code;
      }
      if (hasValidCredentials) {
        progress.complete();
        final emailDisplay = auth.email;
        if (emailDisplay != null) {
          logger
            ..info('You are already logged in as <$emailDisplay>.')
            ..info(
              '''Run ${lightCyan.wrap('shorebird logout')} to log in as a different user.''',
            );
        } else {
          // Env-var auth wins over stored credentials, so `shorebird logout`
          // would not change who this machine is authenticated as.
          logger
            ..info(
              '''You are already authenticated via the $shorebirdTokenEnvVar environment variable.''',
            )
            ..info(
              '''Unset $shorebirdTokenEnvVar to log in as a different user.''',
            );
        }
        return ExitCode.success.code;
      }

      // The stored credentials have expired or been revoked, so discard them
      // and log in again.
      progress.fail('Your credentials have expired.');
      logger.info('Logging you in again...');
      auth.clearCredentials();
    }

    final useDeviceCode = results[deviceFlag] == true || !browser.canOpen;
    try {
      if (useDeviceCode) {
        await auth.loginWithDeviceCode(prompt: devicePrompt);
      } else {
        await auth.login(prompt: prompt);
      }
    } on UserNotFoundException catch (error) {
      final consoleUri = Uri.https('console.shorebird.dev');
      logger
        ..err('''
We could not find a Shorebird account for ${error.email}.''')
        ..info(
          """If you have not yet created an account, you can do so at "${link(uri: consoleUri)}". If you believe this is an error, please reach out to us via Discord, we're happy to help!""",
        );
      return ExitCode.software.code;
    } on Exception catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    logger.info('''

🎉 ${lightGreen.wrap('Welcome to Shorebird! You are now logged in as <${auth.email}>.')}

🔑 Credentials are stored in ${lightCyan.wrap(auth.credentialsFilePath)}.
🚪 To logout use: "${lightCyan.wrap('shorebird logout')}".''');
    return ExitCode.success.code;
  }

  /// Prompt the user to log in, opening [url] in their browser when this
  /// machine has one. The URL is printed either way, so a user whose browser
  /// did not open (or an agent relaying the URL) can still follow it.
  void prompt(String url) {
    final openBrowser = browser.canOpen;
    final instruction = openBrowser
        ? 'Opening your browser to log in. If it does not open, visit this URL:'
        : 'In a browser, visit this URL to log in:';
    logger.info('''
The Shorebird CLI needs your authorization to manage apps, releases, and patches on your behalf.

$instruction

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
    if (openBrowser) unawaited(browser.open(Uri.parse(url)));
  }

  /// Prompt the user to approve [authorization] in a browser on any device.
  ///
  /// Shows the verification URL and the code to type there, never a link
  /// with the code filled in: the auth service wants the code typed for a
  /// session that acts as the user, so a person approves only a code they
  /// read off this terminal.
  void devicePrompt(DeviceAuthorization authorization) {
    final minutes = authorization.expiresIn.inMinutes;
    final url = '${authorization.verificationUri}';
    logger.info(
      '''
The Shorebird CLI needs your authorization to manage apps, releases, and patches on your behalf.

In a browser on any device, visit:

  ${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

and enter this code:

  ${styleBold.wrap(authorization.userCode)}

Waiting for your authorization (the code expires in $minutes ${minutes == 1 ? 'minute' : 'minutes'})...''',
    );
  }
}

/// Whether the auth service answered [error]'s request with a 4xx.
bool _isClientError(ShorebirdAuthException error) {
  final status = error.statusCode;
  return status != null && status >= 400 && status < 500;
}

/// What the auth service answered, as `status error: description`, leaving
/// out whatever it did not send.
String _describeRefusal(ShorebirdAuthException error) {
  final code = error.oauthError;
  final description = error.oauthErrorDescription;
  return [
    '${error.statusCode}',
    if (code != null) ' $code',
    if (code != null && description != null) ': $description',
  ].join();
}
