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
    final CodePushClient client;

    if (!auth.isAuthenticated) {
      try {
        await auth.login(prompt, verifyEmail: false);
        client = buildCodePushClient(
          httpClient: auth.client,
          hostedUri: hostedUri,
        );
      } catch (error) {
        logger.err(error.toString());
        return ExitCode.software.code;
      }
    } else {
      // If the user already has a JWT, check if they already have an account.
      logger.info(
        'Already logged in as ${auth.email}, checking for existing account',
      );

      client = buildCodePushClient(
        httpClient: auth.client,
        hostedUri: hostedUri,
      );

      try {
        final user = await client.getCurrentUser();
        logger.info('''
You already have an account, ${user.displayName}!

To subscribe, run ${green.wrap('shorebird account subscribe')}.
''');
        return ExitCode.success.code;
      } catch (_) {}
    }

    logger.info('Authorized as ${auth.email}');

    final name = logger.prompt('What is your name?');

    final progress = logger.progress('Creating account');
    try {
      final newUser = await client.createUser(name: name);
      final paymentLink = await client.createPaymentLink();
      progress.complete(
        '''

🎉 ${lightGreen.wrap('Welcome to Shorebird, ${newUser.displayName}! You have successfully created an account as <${auth.email}>.')}

🔑 Credentials are stored in ${lightCyan.wrap(auth.credentialsFilePath)}.
🚪 To logout, use: "${lightCyan.wrap('shorebird logout')}".

The next step is to purchase a Shorebird subscription. To subcribe, visit ${lightCyan.wrap('$paymentLink')} or run ${green.wrap('shorebird account subscribe')} later.
''',
      );
      return ExitCode.success.code;
    } catch (error) {
      progress.fail(error.toString());
      return ExitCode.software.code;
    }
  }

  void prompt(String url) {
    logger.info('''
Shorebird is currently only open to trusted testers. To participate, you will need a Google account for authentication.

The first step is to sign in with a Google account. Please follow the sign-in link below:

${styleBold.wrap(styleUnderlined.wrap(lightCyan.wrap(url)))}

Waiting for your authorization...''');
  }
}
