import 'package:cli_io/cli_io.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template login_ci_command}
/// `shorebird login:ci`
/// Deprecated — directs users to API keys instead.
/// {@endtemplate}
class LoginCiCommand extends ShorebirdCommand {
  @override
  String get description => 'Login as a CI user (deprecated).';

  @override
  String get name => 'login:ci';

  @override
  Future<int> run() async {
    logger.info(
      '''
${lightYellow.wrap('⚠ shorebird login:ci is deprecated.')}

To authenticate in CI, create an API key at ${link(uri: Uri.parse('https://console.shorebird.dev'))} and set it as your ${lightCyan.wrap('SHOREBIRD_TOKEN')} environment variable.

Existing tokens from login:ci will continue to work for now, but will stop working in a future release.''',
    );
    return ExitCode.success.code;
  }
}
