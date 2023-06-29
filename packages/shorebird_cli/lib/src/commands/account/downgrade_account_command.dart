import 'dart:async';

import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

class DowngradeAccountCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin {
  DowngradeAccountCommand({super.buildCodePushClient});

  @override
  String get name => 'downgrade';

  @override
  String get description => 'Downgrade your Shorebird account.';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(checkUserIsAuthenticated: true);
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: ShorebirdEnvironment.hostedUri,
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
      logger.err('You do not have a "teams" subscription.');
      return ExitCode.software.code;
    }

    final confirm = logger.confirm(
      red.wrap(
        '''This will downgrade your Shorebird plan to the "hobby" tier. Are you sure?''',
      ),
    );

    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    final progress = logger.progress('Downgrading your plan');

    final DateTime cancellationDate;
    try {
      cancellationDate = await client.cancelSubscription();
    } catch (error) {
      progress.fail('Failed to downgrade plan. Error: $error');
      return ExitCode.software.code;
    }

    final formattedDate = DateFormat.yMMMMd().format(cancellationDate);
    progress.complete(
      '''
Your plan has been downgraded.

Note: Your current plan will continue until $formattedDate, after which your account will be on the "hobby" tier.

Apps on devices you've built with Shorebird will continue to function normally, but will be subject to the limits of the "hobby" tier.''',
    );

    return ExitCode.success.code;
  }
}
