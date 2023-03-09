import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

/// {@template logout_command}
///
/// `shorebird logout`
/// Logout of the current Shorebird user.
/// {@endtemplate}
class LogoutCommand extends ShorebirdCommand {
  /// {@macro logout_command}
  LogoutCommand({required super.logger, super.auth});

  @override
  String get description => 'Logout of the current Shorebird user';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    final session = auth.currentSession;
    if (session == null) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Logging out of shorebird.dev');
    auth.logout();
    logoutProgress.complete();

    return ExitCode.success.code;
  }
}
