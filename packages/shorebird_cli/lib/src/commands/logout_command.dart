import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';

/// {@template logout_command}
///
/// `shorebird logout`
/// Logout of the current Shorebird user.
/// {@endtemplate}
class LogoutCommand extends ShorebirdCommand {
  @override
  String get description => 'Logout of the current Shorebird user';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Logging out of shorebird.dev');
    auth.logout();
    logoutProgress.complete();

    logger.info('${lightGreen.wrap('You are now logged out.')}');

    return ExitCode.success.code;
  }
}
