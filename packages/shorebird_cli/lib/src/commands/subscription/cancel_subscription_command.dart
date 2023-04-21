import 'dart:async';

import 'package:intl/intl.dart';
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
      final currentUser = await client.getCurrentUser();
      if (currentUser == null) {
        throw Exception('Failed to retrieve user information.');
      }
      user = currentUser;
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

    final progress = logger.progress('Canceling your subscription');

    final DateTime cancellationDate;
    try {
      cancellationDate = await client.cancelSubscription();
    } catch (error) {
      progress.fail('Failed to cancel subscription. Error: $error');
      return ExitCode.software.code;
    }

    final formattedDate = DateFormat.yMMMMd().format(cancellationDate);
    progress.complete(
      '''
Your subscription has been canceled.

Note: Your access to Shorebird will continue until $formattedDate, after which all data stored by Shorebird will be deleted as per our privacy policy: https://shorebird.dev/privacy.html.

Apps on devices you've built with Shorebird will continue to function normally, but will not receive further updates.''',
    );

    return ExitCode.success.code;
  }
}
