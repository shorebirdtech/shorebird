import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';

/// {@template logout_command}
///
/// `shorebird logout`
/// Logout of the current Shorebird user.
/// {@endtemplate}
class LogoutCommand extends Command<int> {
  /// {@macro logout_command}
  LogoutCommand({required Auth auth, required Logger logger})
      : _auth = auth,
        _logger = logger;

  @override
  String get description => 'Logout of the current Shorebird user';

  @override
  String get name => 'logout';

  final Auth _auth;
  final Logger _logger;

  @override
  Future<int> run() async {
    final session = _auth.currentSession;
    if (session == null) {
      _logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = _logger.progress('Logging out of shorebird.dev');
    _auth.logout();
    logoutProgress.complete();

    return ExitCode.success.code;
  }
}
