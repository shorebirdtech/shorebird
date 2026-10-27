import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/finish_in_console.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// {@template account_list_command}
/// A command that prints one of the signed-in person's account lists (API
/// keys or sessions) from the auth service's account API, as `npm token
/// list` and `fly tokens list` do.
///
/// The account API lets the CLI's own sign-in read these lists, never change
/// them: creating or revoking a key and signing out a session finish in the
/// console (ADR-0026). When the list can't be read with the credential in
/// use (an API key, GitHub Actions OIDC, or an auth service that predates
/// CLI reads), this opens the console page instead, as before.
/// {@endtemplate}
class AccountListCommand extends ShorebirdCommand with FinishInConsole {
  /// {@macro account_list_command}
  AccountListCommand({
    required this.name,
    required this.commandLine,
    required this.lead,
    required this.apiPath,
    required this.listKey,
    required this.consolePath,
    required this.action,
    required this.manage,
    required this.none,
    required this.describe,
    this.aliases = const [],
  });

  @override
  final String name;

  @override
  final List<String> aliases;

  /// How the command is run, such as `shorebird tokens list`.
  final String commandLine;

  /// The first line of [description], such as "List your API keys.".
  final String lead;

  /// The account API path under the auth service, such as `api/api-keys`.
  final String apiPath;

  /// The key of the list in the account API's response, which `--json`
  /// reports under the same name.
  final String listKey;

  /// The console page that lists and changes these, such as
  /// `account/api-keys`.
  final String consolePath;

  /// What the console page is for, completing "to ...", used when the list
  /// can't be read here.
  final String action;

  /// What the console page does that this command doesn't, completing
  /// "... at" the console URL, such as "Create or revoke a key".
  final String manage;

  /// What to print when the list is empty.
  final String none;

  /// One line describing an entry of the list.
  final String Function(Map<String, dynamic> item) describe;

  @override
  String get description =>
      '$lead\n\n'
      '$manage in the Shorebird console. When you are signed in with '
      'SHOREBIRD_TOKEN or GitHub Actions OIDC, which cannot read this list, '
      'this opens the console instead.\n\n'
      '${ShorebirdCommand.jsonHint('$commandLine --json')}';

  Uri get _consoleUri => ShorebirdWebConsole.uri(consolePath);

  @override
  Future<int> run() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    if (auth.credentialKind != CredentialKind.login) {
      return finishInConsole(action: action, url: _consoleUri);
    }

    final base = shorebirdEnv.authServiceUri;
    final uri = base.replace(path: p.url.join(base.path, apiPath));
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await codePushClientWrapper.codePushClient.send(
          http.Request('GET', uri),
        ),
      );
    } on ProcessExit {
      // The credential already said why it failed and what to do.
      rethrow;
    } on Exception catch (error) {
      return reportError(
        code: JsonErrorCode.fetchFailed,
        message: 'Failed to fetch $uri: $error',
        hint: 'Check your network connection and try again.',
      );
    }

    // An auth service that doesn't yet let the CLI read this list.
    if (response.statusCode == 401 || response.statusCode == 403) {
      logger.detail('GET $uri answered ${response.statusCode}.');
      return finishInConsole(action: action, url: _consoleUri);
    }

    final List<Map<String, dynamic>> items;
    try {
      if (response.statusCode != 200) throw const FormatException();
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      items = [
        for (final item in body[listKey] as List) item as Map<String, dynamic>,
      ];
    } on Object {
      return reportError(
        code: JsonErrorCode.fetchFailed,
        message: response.statusCode == 200
            ? 'Could not read the response from $uri.'
            : 'Failed to fetch $uri: HTTP ${response.statusCode}.',
        hint: 'Try again, or open $_consoleUri in a browser.',
      );
    }

    if (isJsonMode) {
      emitJsonSuccess({listKey: items});
      return ExitCode.success.code;
    }

    if (items.isEmpty) {
      logger.info(none);
    } else {
      for (final item in items) {
        logger.info(describe(item));
      }
    }
    logger.info('\n$manage at ${lightCyan.wrap('$_consoleUri')}');
    return ExitCode.success.code;
  }
}

/// The UTC calendar date of [timestamp], an ISO 8601 string, as YYYY-MM-DD,
/// or [otherwise] when it is null.
String accountListDate(Object? timestamp, {String otherwise = 'never'}) {
  if (timestamp is! String) return otherwise;
  final time = DateTime.tryParse(timestamp);
  if (time == null) return otherwise;
  return time.toUtc().toIso8601String().substring(0, 10);
}
