import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

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
  String get description => 'Sign up for a Shorebird subscription.';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.err('''

You must be logged in to subscribe.

If you have a Shorebird account, run `shorebird login` to log in.
If you don't have a Shorebird account, run `shorebird account create` to create one.
''');
      return ExitCode.software.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final user = await client.getCurrentUser();
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

    logger.info('$paymentLink');

    return ExitCode.success.code;
  }
}
