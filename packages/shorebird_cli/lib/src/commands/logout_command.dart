import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';

/// {@template logout_command}
///
/// `shorebird logout`
/// Logout of the current Shorebird user.
/// {@endtemplate}
class LogoutCommand extends ShorebirdCommand {
  @override
  String get description => 'Logout of the current Shorebird user.';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Logging out of shorebird.dev');
    final revoked = await auth.logout();
    logoutProgress.complete();

    logger.info('${lightGreen.wrap('You are now logged out.')}');
    if (!revoked) {
      logger.warn(
        '''Unable to confirm with the auth server that the session was terminated. Credentials were deleted locally. To confirm, you can see and manage your sessions at ${link(uri: ShorebirdWebConsole.uri('account'))}.''',
      );
    }

    return ExitCode.success.code;
  }
}
