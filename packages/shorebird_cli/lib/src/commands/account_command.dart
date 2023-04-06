import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

class AccountCommand extends ShorebirdCommand {
  AccountCommand({required super.logger, super.auth});

  @override
  String get name => 'account';

  @override
  String get description => 'Show information about the logged-in user';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.info(
        'You are not logged in.'
        ' Run ${green.wrap('shorebird login')} to log in.',
      );
      return ExitCode.success.code;
    }

    logger.info('You are logged in as <${auth.user!.email}>');

    return ExitCode.success.code;
  }
}
