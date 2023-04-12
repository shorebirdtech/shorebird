import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class CancelSubscriptionCommand extends ShorebirdCommand
    with ShorebirdConfigMixin {
  CancelSubscriptionCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
  });

  @override
  String get name => 'cancel';

  @override
  String get description => 'Cancel your Shorebird subscription.';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.err('You must be logged in to cancel your subscription.');
      return ExitCode.noUser.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final User user;
    try {
      user = await client.getCurrentUser();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    if (!user.hasActiveSubscription) {
      logger.err('You do not have an active subscription.');
      return ExitCode.software.code;
    }

    final confirm = logger.confirm(
      red.wrap('This will cancel your Shorebird subscription. Are you sure?'),
    );
    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    try {
      await client.cancelSubscription();
    } catch (error) {
      logger.err(error.toString());
      return ExitCode.software.code;
    }

    logger.info('Your subscription has been canceled.');

    return ExitCode.success.code;
  }
}
