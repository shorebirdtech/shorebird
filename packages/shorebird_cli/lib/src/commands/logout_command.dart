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
          'opens it. API keys stay valid; revoke them with '
          '`shorebird tokens delete`.',
    );
  }

  @override
  String get description => 'Logout of the current Shorebird user.';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    final all = results['all'] == true;
    final exitCode = await _logOutHere(warnUnconfirmed: !all);
    if (!all) return exitCode;
    // This machine is logged out either way; say so in the action, since a
    // non-interactive run reports only the hand-off.
    return finishInConsole(
      action: 'sign out your other sessions (this one is logged out)',
      url: ShorebirdWebConsole.uri('account'),
    );
  }

  /// Logs out on this machine. [warnUnconfirmed] says where to check when
  /// the server did not confirm the session ended; `--all` sends the user
  /// there anyway.
  Future<int> _logOutHere({required bool warnUnconfirmed}) async {
    if (!auth.isAuthenticated) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Logging out of shorebird.dev');
    final revoked = await auth.logout();
    logoutProgress.complete();

    logger.info('${lightGreen.wrap('You are now logged out.')}');
    if (!revoked && warnUnconfirmed) {
      logger.warn(
        '''Unable to confirm with the auth server that the session was terminated. Credentials were deleted locally. If you would like to confirm, you can see and manage your sessions at ${link(uri: ShorebirdWebConsole.uri('account'))}.''',
      );
    }

    return ExitCode.success.code;
  }
}
