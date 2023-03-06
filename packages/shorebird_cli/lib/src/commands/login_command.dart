import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';

/// {@template login_command}
///
/// `shorebird login`
/// Login as a new Shorebird user.
/// {@endtemplate}
class LoginCommand extends Command<int> {
  /// {@macro login_command}
  LoginCommand({required Auth auth, required Logger logger})
      : _auth = auth,
        _logger = logger;

  @override
  String get description => 'Login as a new Shorebird user.';

  @override
  String get name => 'login';

  final Auth _auth;
  final Logger _logger;

  @override
  Future<int> run() async {
    final session = _auth.currentSession;
    if (session != null) {
      _logger
        ..info('You are already logged in.')
        ..info("Run 'shorebird logout' to log out and try again.");
      return ExitCode.success.code;
    }

    final apiKey = _logger.prompt(
      '${lightGreen.wrap('?')} Please enter your API Key:',
    );
    final loginProgress = _logger.progress('Logging into shorebird.dev');
    try {
      _auth.login(projectId: 'example', apiKey: apiKey);
      loginProgress.complete();
      _logger.success('You are now logged in.');
      return ExitCode.success.code;
    } catch (error) {
      loginProgress.fail();
      _logger.err(error.toString());
      return ExitCode.software.code;
    }
  }
}
