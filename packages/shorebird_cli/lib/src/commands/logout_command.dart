import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';

/// {@template logout_command}
///
/// `shorebird logout`
/// Logout of the current Shorebird user.
/// {@endtemplate}
class LogoutCommand extends ShorebirdCommand with FinishInConsole {
  /// {@macro logout_command}
  LogoutCommand() {
    argParser.addFlag(
      'all',
      negatable: false,
      help:
          'Also sign out every other session (other machines, the console), '
          'which is done in the Shorebird console: this logs out here, then '
          'opens it.',
    );
  }

  @override
  String get description => 'Logout of the current Shorebird user.';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    final exitCode = await _logOutHere();
    if (results['all'] != true) return exitCode;
    return finishInConsole(
      action: 'sign out of every other session',
      url: ShorebirdWebConsole.uri('account'),
    );
  }

  Future<int> _logOutHere() async {
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
        '''Unable to confirm with the auth server that the session was terminated. Credentials were deleted locally. If you would like to confirm, you can see and manage your sessions at ${link(uri: ShorebirdWebConsole.uri('account'))}.''',
      );
    }

    return ExitCode.success.code;
  }
}
