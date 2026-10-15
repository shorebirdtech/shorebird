import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/jq.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template api_command}
/// `shorebird api <endpoint>`
/// Makes an authenticated HTTP request to the Shorebird API and prints the
/// response.
/// {@endtemplate}
///
/// Modeled on `gh api` (https://cli.github.com/manual/gh_api), so that the
/// flags agents and scripts already use there work here too.
class ApiCommand extends ShorebirdCommand {
  /// {@macro api_command}
  ApiCommand() {
    argParser
      ..addOption(
        'method',
        abbr: 'X',
        defaultsTo: 'GET',
        help: 'The HTTP method for the request.',
      )
      ..addMultiOption(
        'field',
        abbr: 'F',
        valueHelp: 'key=value',
        splitCommas: false,
        help:
            'Add a typed parameter in key=value format (use "@<path>" or '
            '"@-" to read value from file or stdin).',
      )
      ..addMultiOption(
        'raw-field',
        abbr: 'f',
        valueHelp: 'key=value',
        splitCommas: false,
        help: 'Add a string parameter in key=value format.',
      )
      ..addOption(
        'input',
        valueHelp: 'file',
        help:
            'The file to use as body for the HTTP request (use "-" to read '
            'from standard input).',
      )
      ..addFlag(
        'paginate',
        negatable: false,
        help:
            'Make additional requests to fetch every page of a list '
            '(GET only).',
      )
      ..addFlag(
        'slurp',
        negatable: false,
        help:
            'With --paginate, print one JSON array of every page instead of '
            'each page in turn.',
      )
      ..addOption(
        'jq',
        abbr: 'q',
        valueHelp: 'expression',
        help:
            'Query to select values from the response using jq syntax (a '
            'common subset; see above).',
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help:
            'The product flavor whose app ID fills the {appId} placeholder '
            '(from shorebird.yaml).',
      );
  }

  /// The exit code for a request that failed: a non-2xx response, no
  /// response at all, or a `--jq` query that failed. `gh api` exits 1.
  static const requestFailedExitCode = 1;

  /// The placeholder replaced with the current project's app ID.
  static const appIdPlaceholder = '{appId}';

  /// The query parameter that asks a list for a page of a given size.
  static const perPageParameter = 'per_page';

  /// The page size --paginate asks for when the request does not set one:
  /// the largest the API allows, as `gh api --paginate` does.
  static const paginatePerPage = 100;

  /// The query parameter that asks a list for the page after a cursor.
  static const cursorParameter = 'cursor';

  /// The response body field that holds the next page's cursor. A list
  /// leaves it out on its last page.
  static const nextCursorField = 'next_cursor';

  @override
  String get name => 'api';

  @override
  String get invocation => 'shorebird api <endpoint> [arguments]';

  @override
  bool get reservesStdout => true;

  @override
  String get description =>
      '''
Makes an authenticated HTTP request to the Shorebird API and prints the response.

The endpoint argument is a path relative to https://api.shorebird.dev/api/v1, such as "/apps" or "apps/{appId}/releases". A full URL under https://api.shorebird.dev/api/v1 is accepted too; URLs on any other host are rejected, so your credentials are only ever sent to the Shorebird API.

The placeholder "$appIdPlaceholder" in the endpoint, and in -F/--field values, is replaced with the app ID from the current project's shorebird.yaml. Pass --flavor to use a flavor's app ID.

The default HTTP request method is "GET" normally and "POST" if any fields or --input were added. Override the method with --method.

Pass one or more -f/--raw-field values in "key=value" format to add string parameters. -F/--field converts its value: "true", "false", "null" and integers become JSON values, "@<path>" reads the value from a file ("@-" from standard input), and "$appIdPlaceholder" is filled in. For "GET" requests, fields are sent as the query string; otherwise they are sent as a JSON object body. For a nested JSON body, use --input.

--input sends a JSON file (or "-" for standard input) as the request body. Fields are then added to the query string.

The response body is printed as-is (JSON is indented when printing to a terminal). On a non-2xx response the body is still printed, an error is printed to stderr, and the command exits with status 1.

--paginate fetches every page of a list. It asks for $paginatePerPage items per page unless the request sets "$perPageParameter", then follows each page's "$nextCursorField" until the last page, printing each page in turn (and applying --jq to each). It is for GET requests only, and makes the method default to GET even when fields are added. Add --slurp to print a single JSON array holding every page instead. If a page fails, the pages before it have already been printed and the command exits with status 1.

--jq takes a jq expression and prints each result: strings without quotes, other values as JSON. It supports a common subset of jq: paths (".", ".a.b", ".[]", ".[0]", "?"), "|", ",", comparisons, "and", "or", "not", object and array construction, string interpolation, and length, keys, map(f), select(f), empty, first, first(f), last, sort_by(f), unique, unique_by(f), join(sep), to_entries, from_entries and with_entries(f).

Requests are authenticated as your "shorebird login" session, or with the API key in the SHOREBIRD_TOKEN environment variable. Requests other than GET are never retried, so a write is sent at most once.

The API reference is at https://api.shorebird.dev/openapi.json, and guides are at https://docs.shorebird.dev/account/api/. The API is published, but it has no compatibility guarantee yet: routes and response shapes may change.

Examples:
  # List the apps you have access to
  \$ shorebird api /apps

  # List the release versions of the app in the current project
  \$ shorebird api /apps/{appId}/releases --jq '.releases[].version'

  # Create a channel
  \$ shorebird api /apps/{appId}/channels -f channel=beta

  # Add parameters to a GET request
  \$ shorebird api -X GET /apps/{appId}/metrics/patch-installs -f granularity=day

  # List the IDs of every release of the app, fetching all pages
  \$ shorebird api /apps/{appId}/releases --paginate --jq '.releases[].id'

  # Use a JSON file as request body
  \$ shorebird api -X PATCH /apps/{appId}/releases/123 --input release.json''';

  @override
  Future<int> run() {
    // Only the response goes to stdout. Everything else printed while the
    // command runs, such as the "shorebird login" hints when you are not
    // logged in or a token refresh fails, goes to stderr.
    _output = stdout;
    return runWithStdoutOnStderr(_run);
  }

  /// Where the response is printed: the real stdout.
  late Stdout _output;

  Future<int> _run() async {
    if (isJsonMode) {
      usageException(
        'shorebird api prints the response body as-is and does not support '
        '--json.',
      );
    }
    if (results.rest.length != 1) {
      usageException(
        'Expected exactly one <endpoint> argument, got '
        '${results.rest.length}.',
      );
    }
    final jqSource = results['jq'] as String?;
    JqQuery? jq;
    if (jqSource != null) {
      try {
        jq = JqQuery.parse(jqSource);
      } on JqException catch (error) {
        usageException('--jq: ${error.message}');
      }
    }

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final params = <String, Object?>{
      for (final field in results['raw-field'] as List<String>)
        _fieldKey(field): _fieldValue(field),
    };
    for (final field in results['field'] as List<String>) {
      params[_fieldKey(field)] = await _typedValue(_fieldValue(field));
    }

    final inputPath = results['input'] as String?;
    final paginate = results['paginate'] as bool;
    final slurp = results['slurp'] as bool;
    if (slurp && !paginate) {
      usageException('--slurp requires --paginate.');
    }
    if (slurp && jq != null) {
      usageException('--slurp cannot be used with --jq.');
    }
    var method = (results['method'] as String).toUpperCase();
    if (!results.wasParsed('method') &&
        !paginate &&
        (params.isNotEmpty || inputPath != null)) {
      method = 'POST';
    }
    if (paginate && method != 'GET') {
      usageException(
        'the --paginate option is not supported for non-GET requests.',
      );
    }

    final codePushClient = codePushClientWrapper.codePushClient;
    final apiBase = '${codePushClient.apiBaseUri}';
    var endpoint = results.rest.single;
    if (endpoint.contains('://')) {
      // A full URL is accepted when it is on the API, and used as its path.
      if (endpoint != apiBase && !endpoint.startsWith('$apiBase/')) {
        usageException(
          'Only URLs under $apiBase are accepted, so your credentials are '
          'never sent elsewhere. Pass the path instead, such as "/apps".',
        );
      }
      endpoint = endpoint.substring(apiBase.length);
    }
    endpoint = _fillPlaceholders(endpoint);
    final path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    var url = '$apiBase/$path';

    List<int>? body;
    if (inputPath != null) {
      body = await _readUserFile(inputPath, flag: '--input');
      url = _addQuery(url, params);
    } else if (params.isNotEmpty) {
      if (method == 'GET') {
        url = _addQuery(url, params);
      } else {
        body = utf8.encode(jsonEncode(params));
      }
    }

    var uri = Uri.parse(url);
    if (paginate && !uri.queryParameters.containsKey(perPageParameter)) {
      uri = _withQueryParameter(uri, perPageParameter, '$paginatePerPage');
    }

    final indent = _output.hasTerminal ? '  ' : '';
    // The cursors already followed, so a server that hands one back again
    // cannot send this into an endless loop.
    final followed = <String>{};
    final slurped = <Object?>[];
    while (true) {
      final request = http.Request(method, uri)..headers['accept'] = '*/*';
      if (body != null) {
        // Every route that takes a body takes JSON.
        request
          ..headers['content-type'] = 'application/json; charset=utf-8'
          ..bodyBytes = body;
      }

      final http.StreamedResponse response;
      final Uint8List responseBody;
      try {
        // A write that failed may still have reached the server, so only
        // GETs are retried.
        (response, responseBody) = await runScoped(
          () async {
            final response = await codePushClient.send(request);
            return (response, await response.stream.toBytes());
          },
          values: {retryFailedRequestsRef.overrideWith(() => method == 'GET')},
        );
      } on http.ClientException catch (error) {
        return _fail(error.message);
      } on SocketException catch (error) {
        return _fail(error.message);
      }

      if (response.statusCode == HttpStatus.noContent) break;

      final contentType = response.headers['content-type'] ?? '';
      final isJson = RegExp(r'[/+]json(;|$)').hasMatch(contentType);
      final succeeded =
          response.statusCode >= 200 && response.statusCode <= 299;

      if (!succeeded) {
        final pretty = isJson && indent.isNotEmpty
            ? _prettyJson(responseBody)
            : null;
        if (pretty != null) {
          _output.writeln(pretty);
        } else {
          _output.add(responseBody);
        }
        return _fail(
          (isJson ? _errorMessage(responseBody, response.statusCode) : null) ??
              'HTTP ${response.statusCode}',
        );
      }

      // The decoded body, when something needs it: --jq, --slurp, or
      // --paginate looking for the next page.
      Object? decoded;
      var decodedOk = false;
      if (jq != null || slurp || (paginate && isJson)) {
        try {
          decoded = jsonDecode(utf8.decode(responseBody));
          decodedOk = true;
        } on FormatException {
          if (jq != null) return _fail('--jq: the response is not JSON');
          if (slurp) return _fail('--slurp: the response is not JSON');
        }
      }

      if (slurp) {
        slurped.add(decoded);
      } else if (jq != null) {
        try {
          for (final value in jq.evaluate(decoded)) {
            _output.writeln(JqQuery.format(value, indent: indent));
          }
        } on JqException catch (error) {
          return _fail('--jq: ${error.message}');
        }
      } else {
        final pretty = isJson && indent.isNotEmpty
            ? _prettyJson(responseBody)
            : null;
        if (pretty != null) {
          _output.writeln(pretty);
        } else {
          _output.add(responseBody);
          // Keeps pages apart, one JSON document per line.
          if (paginate &&
              responseBody.isNotEmpty &&
              responseBody.last != 0x0a) {
            _output.writeln();
          }
        }
      }

      if (!paginate || !decodedOk) break;
      final next = decoded is Map<String, dynamic>
          ? decoded[nextCursorField]
          : null;
      if (next is! String || next.isEmpty) break;
      if (!followed.add(next)) {
        return _fail(
          '--paginate: the server returned the cursor "$next" twice; '
          'stopping.',
        );
      }
      uri = _withQueryParameter(uri, cursorParameter, next);
    }

    if (slurp) {
      _output.writeln(
        indent.isEmpty
            ? jsonEncode(slurped)
            : JsonEncoder.withIndent(indent).convert(slurped),
      );
    }
    return ExitCode.success.code;
  }

  /// [uri] with the query parameter [key] set to [value], replacing any
  /// value it had and keeping every other parameter.
  static Uri _withQueryParameter(Uri uri, String key, String value) =>
      uri.replace(
        queryParameters: {
          ...uri.queryParametersAll,
          key: [value],
        },
      );

  int _fail(String message) {
    stderr.writeln('shorebird: $message');
    return requestFailedExitCode;
  }

  String? _appId;

  /// Replaces each [appIdPlaceholder] in [value] with the current project's
  /// app ID, as `gh api` replaces `{owner}` and `{repo}`.
  String _fillPlaceholders(String value) => value.contains(appIdPlaceholder)
      ? value.replaceAll(appIdPlaceholder, _appId ??= _resolveAppId())
      : value;

  String _resolveAppId() {
    final shorebirdYaml = shorebirdEnv.getShorebirdYaml();
    if (shorebirdYaml == null) {
      usageException(
        'unable to expand placeholder $appIdPlaceholder: no shorebird.yaml '
        'found in this directory or its parents. Run this command from a '
        'Shorebird project, or put the app ID in the endpoint.',
      );
    }
    final flavor = results[CommonArguments.flavorArg.name] as String?;
    final flavorError = shorebirdYaml.unknownFlavorError(flavor);
    if (flavorError != null) usageException(flavorError);
    return shorebirdYaml.getAppId(flavor: flavor);
  }

  int _fieldSeparator(String field) {
    final separator = field.indexOf('=');
    if (separator < 1) {
      usageException('field "$field" must be in key=value format');
    }
    return separator;
  }

  String _fieldKey(String field) => field.substring(0, _fieldSeparator(field));

  String _fieldValue(String field) =>
      field.substring(_fieldSeparator(field) + 1);

  /// Converts a -F/--field value the way `gh api` does.
  Future<Object?> _typedValue(String value) async {
    if (value.startsWith('@')) {
      final bytes = await _readUserFile(value.substring(1), flag: '--field');
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (RegExp(r'^[+-]?\d+$').hasMatch(value)) {
      final number = int.tryParse(value);
      if (number != null) return number;
    }
    return switch (value) {
      'true' => true,
      'false' => false,
      'null' => null,
      _ => _fillPlaceholders(value),
    };
  }

  /// Reads [path], or stdin when [path] is `-`.
  Future<List<int>> _readUserFile(String path, {required String flag}) async {
    if (path == '-') {
      final builder = BytesBuilder(copy: false);
      await stdin.forEach(builder.add);
      return builder.takeBytes();
    }
    final file = File(path);
    if (!file.existsSync()) usageException('$flag: no file found at $path.');
    return file.readAsBytes();
  }

  static String _addQuery(String url, Map<String, Object?> params) {
    if (params.isEmpty) return url;
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent('${e.value ?? ''}')}',
        )
        .join('&');
    return '$url${url.contains('?') ? '&' : '?'}$query';
  }

  static String? _prettyJson(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } on FormatException {
      return null;
    }
  }

  /// The error `gh api` reports for a JSON error body: its `message`
  /// followed by the HTTP status, or null if it has none.
  static String? _errorMessage(List<int> body, int statusCode) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) {
          return '$message (HTTP $statusCode)';
        }
      }
    } on FormatException {
      // Not JSON after all: fall back to the bare status.
    }
    return null;
  }
}
