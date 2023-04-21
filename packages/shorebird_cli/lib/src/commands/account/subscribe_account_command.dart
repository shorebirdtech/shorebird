import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template subscribe_account_command}
/// `shorebird account subscribe`
/// {@endtemplate}
class SubscribeAccountCommand extends ShorebirdCommand
    with ShorebirdConfigMixin {
  /// {@macro subscribe_account_command}
  SubscribeAccountCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  });

  @override
  String get name => 'subscribe';

  @override
  String get description => 'Sign up for a Shorebird subscription .';

  @override
  String get summary => '''
A subscription is required to use Shorebird to create and publish apps.
Subscriptions are currently \$20 per month and are billed through Stripe.
Visit ${styleUnderlined.wrap(lightCyan.wrap('https://github.com/shorebirdtech/shorebird/blob/main/TRUSTED_TESTERS.md'))} to learn more.''';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger
        ..err('''
You must be logged in to subscribe.''')
        ..info('''

If you have a Shorebird account, run ${lightCyan.wrap('shorebird login')} to log in.
If you don't have a Shorebird account, run ${lightCyan.wrap('shorebird account create')} to create one.''');
      return ExitCode.software.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final progress = logger.progress('Retrieving account information');

    final User? user;
    try {
      user = await client.getCurrentUser();
      if (user == null) {
        progress.fail('''
We're having trouble retrieving your account information.

Please try logging out using ${lightCyan.wrap('shorebird logout')} and logging back in using ${lightCyan.wrap('shorebird login')}. If this problem persists, please contact us on Discord.''');
        return ExitCode.software.code;
      }
    } catch (error) {
      progress.fail(error.toString());
      return ExitCode.software.code;
    }

    if (user.hasActiveSubscription) {
      progress.complete('You already have an active subscription. Thank you!');
      return ExitCode.success.code;
    } else {
      progress.update('Retrieved account information, generating payment link');
    }

    final Uri paymentLink;
    try {
      paymentLink = await client.createPaymentLink();
    } catch (error) {
      progress.fail(error.toString());
      return ExitCode.software.code;
    }

    progress.complete('Link generated!');

    logger.info('''

To purchase a Shorebird subscription, please visit the following link:
${lightCyan.wrap(paymentLink.toString())}

Once Stripe has processed your payment, you will be able to use Shorebird to create and publish apps.

${styleBold.wrap(red.wrap('Note: This payment link is specifically for ${styleItalic.wrap('your account')}. Do not share it with others.'))}''');

    return ExitCode.success.code;
  }
}
