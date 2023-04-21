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
Subscriptions are \$20 per month and are billed through Stripe.
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

    final User user;
    try {
      final maybeUser = await client.getCurrentUser();
      if (maybeUser == null) {
        logger.err('''
We're having trouble retrieving your account information.

Please try logging out using ${lightCyan.wrap('shorebird logout')} and logging back in using ${lightCyan.wrap('shorebird login')}. If this problem persists, please contact us on Discord.''');
        return ExitCode.software.code;
      }
      user = maybeUser;
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    if (user.hasActiveSubscription) {
      logger.info('You already have an active subscription. Thank you!');
      return ExitCode.success.code;
    }

    final Uri paymentLink;
    try {
      paymentLink = await client.createPaymentLink();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    logger.info('''

To purchase a Shorebird subscription, please visit the following link:
${lightCyan.wrap(paymentLink.toString())}

Once Stripe has processed your payment, you will be able to use Shorebird to create and publish apps.''');

    return ExitCode.success.code;
  }
}
