import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_documentation.dart';

/// {@template login_ci_command}
/// `shorebird login:ci`
/// Removed — directs users to service account keys instead.
/// {@endtemplate}
class LoginCiCommand extends ShorebirdCommand {
  @override
  String get description => 'Removed — use a service account key instead.';

  @override
  String get name => 'login:ci';

  @override
  Future<int> run() async {
    logger.err(
      '''
shorebird login:ci has been replaced by API keys. For CI, use a service account key.

Create a service account key and set it as your ${lightCyan.wrap('SHOREBIRD_TOKEN')} environment variable.

Learn more: ${serviceAccountsUrl.toLink()}''',
    );
    return ExitCode.usage.code;
  }
}
