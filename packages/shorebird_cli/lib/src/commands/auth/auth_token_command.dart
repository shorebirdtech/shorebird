import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
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
      'expired, and otherwise printed as is, so it may expire soon after: get '
      'a new one each time rather than storing it. With an API key from '
      '$shorebirdTokenEnvVar, prints the key. Treat the output as a secret; '
      "it is left out of the run's log file.\n\n"
      '${ShorebirdCommand.jsonHint('shorebird auth token --json')}';

  @override
  bool get reservesStdout => true;

  /// Writes only the token (or its `--json` envelope) to stdout, so that
  /// `$(shorebird auth token)` captures nothing else: every other line,
  /// including a failure's hint and `--verbose` output, goes to stderr.
  ///
  /// The token is a secret, so it skips the copy of stdout kept in this run's
  /// log file ([LoggingStdout]), which users are asked to attach to bug
  /// reports.
  @override
  Future<int> run() {
    final sink = isJsonMode ? read(jsonSinkRef, orElse: () => stdout) : stdout;
    final output = sink is LoggingStdout ? sink.baseStdOut : sink;
    return runWithStdoutOnStderr(
      () => runScoped(
        () => _run(output),
        values: {jsonSinkRef.overrideWith(() => output)},
      ),
    );
  }

  Future<int> _run(IOSink output) async {
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

    output.writeln(token);
    return ExitCode.success.code;
  }
}
