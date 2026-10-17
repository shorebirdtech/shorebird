import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template auth_status_command}
/// `shorebird auth status`
/// Show which credential the CLI authenticates with and who it acts as.
/// {@endtemplate}
class AuthStatusCommand extends ShorebirdCommand {
  /// {@macro auth_status_command}
  AuthStatusCommand();

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show which credential the CLI authenticates with and who it acts '
      'as.\n\n'
      'Credentials are tried in this order: an API key from '
      '$shorebirdTokenEnvVar (a personal access token or a service account '
      'key), then GitHub Actions OIDC, then your `shorebird login`.\n\n'
      'Example output:\n'
      '  Credential:  Login (shorebird login)\n'
      '  Acting as:   user@example.com (ID 42)\n'
      '  Expires:     2026-10-17T01:00:00.000Z\n\n'
      'Expires is when the current access token expires. A login and GitHub '
      'Actions OIDC get a new one automatically. An API key has no access '
      'token to expire, so the line is left out.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird auth status --json')}';

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    late final PrivateUser user;
    final fetchError = await guardApiCall(
      () async => user = await codePushClientWrapper.getCurrentUser(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch account.',
    );
    if (fetchError != null) return fetchError;

    // The request above resolved the credential, so these describe the one
    // that authenticated it.
    final kind = auth.credentialKind;
    final expiresAt = auth.accessTokenExpiresAt?.toUtc();

    if (isJsonMode) {
      emitJsonSuccess({
        'credential': kind?.jsonName,
        'user': {'id': user.id, 'email': user.email},
        'expires_at': expiresAt?.toIso8601String(),
      });
      return ExitCode.success.code;
    }

    logger
      ..info('Credential:  ${kind?.description ?? 'unknown'}')
      ..info('Acting as:   ${user.email} (ID ${user.id})');
    if (expiresAt != null) {
      logger.info('Expires:     ${expiresAt.toIso8601String()}');
    }
    return ExitCode.success.code;
  }
}
