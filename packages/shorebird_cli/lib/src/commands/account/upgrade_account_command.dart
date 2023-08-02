import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template upgrade_account_command}
/// `shorebird account upgrade`
/// {@endtemplate}
class UpgradeAccountCommand extends ShorebirdCommand {
  /// {@macro upgrade_account_command}
  UpgradeAccountCommand({super.buildCodePushClient});

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade your Shorebird account.';

  @override
  Future<int> run() async {
    final consoleLink = link(uri: Uri.parse('https://console.shorebird.dev'));
    logger.warn(
      '''
This command is deprecated and will be removed in a future release.
Please use $consoleLink instead.''',
    );

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final client = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: ShorebirdEnvironment.hostedUri,
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

${styleBold.wrap(red.wrap('Note: This payment link is specifically for ${styleItalic.wrap('your account')}. Do not share it with others.'))}

Once you have completed your payment, please let us know on Discord or by
replying to your invite email, so that we can add you to the support channel for live support.

Thanks for you help!
''');
    return ExitCode.success.code;
  }
}
