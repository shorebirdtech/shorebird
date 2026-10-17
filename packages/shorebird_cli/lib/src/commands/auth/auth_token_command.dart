import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template auth_token_command}
/// `shorebird auth token`
/// Print the access token the CLI would send with its next request.
/// {@endtemplate}
class AuthTokenCommand extends ShorebirdCommand {
  /// {@macro auth_token_command}
  AuthTokenCommand();

  @override
  String get name => 'token';

  @override
  List<String> get aliases => const ['print-access-token'];

  @override
  String get description =>
      'Print the access token the CLI sends to the Shorebird API.\n\n'
      'For calling the API from another tool:\n'
      r'  curl -H "Authorization: Bearer $(shorebird auth token)" '
      'https://api.shorebird.dev/api/v1/users/me\n\n'
      'A login or GitHub Actions OIDC token is refreshed first if it has '
      'expired. With an API key from $shorebirdTokenEnvVar, prints the key. '
      'Treat the output as a secret.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird auth token --json')}';

  @override
  bool get reservesStdout => true;

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final String token;
    final tokenError = await guardApiCall(
      () async => token = await auth.accessToken(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to get an access token.',
    );
    if (tokenError != null) return tokenError;

    if (isJsonMode) {
      emitJsonSuccess({
        'token': token,
        'credential': auth.credentialKind?.jsonName,
        'expires_at': auth.accessTokenExpiresAt?.toUtc().toIso8601String(),
      });
      return ExitCode.success.code;
    }

    logger.info(token);
    return ExitCode.success.code;
  }
}
