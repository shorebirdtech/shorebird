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
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

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
        help:
            'The HTTP method for the request. It can also be passed before '
            'the endpoint, as in "shorebird api DELETE <endpoint>".',
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
      ..addOption(
        'jq',
        abbr: 'q',
        valueHelp: 'expression',
        help:
            'Query to select values from the response using jq syntax (a '
            'common subset; see above).',
      )
      ..addFlag(
        'paginate',
        negatable: false,
        help:
            'Make additional requests to fetch every page, and print them '
            'merged into one response.',
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

  /// The HTTP methods accepted before the endpoint, as in
  /// `shorebird api GET /apps`.
  static const positionalMethods = {
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
  };

  /// The response fields that carry the next page's cursor: `next_cursor`
  /// on the paged list routes, `nextCursor` on the older audit log route.
  static const _cursorKeys = ['next_cursor', 'nextCursor'];

  @override
  String get name => 'api';

  @override
  String get invocation => 'shorebird api [<method>] <endpoint> [arguments]';

  @override
  bool get reservesStdout => true;

  @override
  String get description =>
      '''
Makes an authenticated HTTP request to the Shorebird API and prints the response.

The endpoint argument is a path relative to https://api.shorebird.dev/api/v1, such as "/apps" or "apps/{appId}/releases". A full URL under https://api.shorebird.dev/api/v1 is accepted too; URLs on any other host are rejected, so your credentials are only ever sent to the Shorebird API.

The placeholder "$appIdPlaceholder" in the endpoint, and in -F/--field values, is replaced with the app ID from the current project's shorebird.yaml. Pass --flavor to use a flavor's app ID.

The default HTTP request method is "GET" normally and "POST" if any fields or --input were added. Override the method by passing it before the endpoint, as in "shorebird api DELETE /apps/{appId}/releases/123", or with --method.

Pass one or more -f/--raw-field values in "key=value" format to add string parameters. -F/--field converts its value: "true", "false", "null" and integers become JSON values, "@<path>" reads the value from a file ("@-" from standard input), and "$appIdPlaceholder" is filled in. For "GET" requests, fields are sent as the query string; otherwise they are sent as a JSON object body. Adding fields switches the default method to "POST", so to send them as a "GET" query string, pass --method GET. For a nested JSON body, use --input.

--input sends a JSON file (or "-" for standard input) as the request body. Fields are then added to the query string.

The response body is printed as-is (JSON is indented when printing to a terminal). On a non-2xx response the body is still printed, an error is printed to stderr, and the command exits with status 1.

--paginate fetches every page of a list. While a response has a "next_cursor" (or "nextCursor"), the same request is sent again with "cursor" set to it. The pages are printed as one JSON object: list fields are concatenated and the cursor is dropped. --jq applies to the merged object. A response without a cursor is printed as it is, so --paginate is safe on any endpoint. --paginate only works with GET, so fields become the query string, and it does not work with --input.

--jq takes a jq expression and prints each result: strings without quotes, other values as JSON. It supports a common subset of jq: paths (".", ".a.b", ".[]", ".[0]", "?"), slices (".[1:3]", ".[2:]", ".[:-1]"), "|", ",", comparisons, "and", "or", "not", object and array construction, string interpolation, and length, keys, map(f), select(f), empty, first, first(f), last, sort_by(f), unique, unique_by(f), join(sep), to_entries, from_entries and with_entries(f).

Requests are authenticated as your "shorebird login" session, or with the API key in the SHOREBIRD_TOKEN environment variable. Requests other than GET are never retried, so a write is sent at most once.

The API reference is at https://api.shorebird.dev/openapi.json, and guides are at https://docs.shorebird.dev/account/api/. The API is published, but it has no compatibility guarantee yet: routes and response shapes may change.

Examples:
  # List the apps you have access to
  \$ shorebird api /apps

  # List the release versions of the app in the current project
  \$ shorebird api /apps/{appId}/releases --jq '.releases[].version'

  # Create a channel
  \$ shorebird api /apps/{appId}/channels -f channel=beta

  # Delete a release, passing the method before the endpoint
  \$ shorebird api DELETE /apps/{appId}/releases/123

  # Print every audit log action, across all pages
  \$ shorebird api /organizations/123/audit-logs --paginate --jq '.data[].action'

  # Add parameters to a GET request
  \$ shorebird api -X GET /apps/{appId}/metrics/patch-installs -f granularity=day

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
    final rest = results.rest;
    String? positionalMethod;
    if (rest.length == 2) {
      positionalMethod = rest.first.toUpperCase();
      if (!positionalMethods.contains(positionalMethod)) {
        usageException(
          '"${rest.first}" is not an HTTP method. Pass the endpoint alone, or '
          'the method and then the endpoint, as in "shorebird api GET /apps". '
          'Methods: ${positionalMethods.join(', ')}.',
        );
      }
    } else if (rest.length != 1) {
      usageException(
        'Expected exactly one <endpoint> argument, optionally after the HTTP '
        'method (as in "shorebird api GET /apps"), got ${rest.length}.',
      );
    }
    final endpointArg = rest.last;
    final flagMethod = (results['method'] as String).toUpperCase();
    if (positionalMethod != null &&
        results.wasParsed('method') &&
        flagMethod != positionalMethod) {
      usageException(
        'The method is given twice, as "$positionalMethod" and as --method '
        '$flagMethod. Pass one of them.',
      );
    }
    final explicitMethod =
        positionalMethod ?? (results.wasParsed('method') ? flagMethod : null);
    final paginate = results['paginate'] as bool;
    if (paginate && explicitMethod != null && explicitMethod != 'GET') {
      usageException(
        '--paginate only works with GET requests, not $explicitMethod.',
      );
    }
    if (paginate && results.wasParsed('input')) {
      usageException(
        '--paginate sends GET requests, which take no body, so it does not '
        'work with --input. Pass parameters with -f/--raw-field instead.',
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
    var method = explicitMethod ?? 'GET';
    final methodDefaulted = explicitMethod == null;
    // --paginate keeps the default GET, so its fields page a list.
    if (methodDefaulted &&
        !paginate &&
        (params.isNotEmpty || inputPath != null)) {
      method = 'POST';
    }
    // Whether fields alone made this a POST, which a caller who meant them
    // as a GET query string may not expect.
    final fieldsMadePost =
        methodDefaulted &&
        method == 'POST' &&
        params.isNotEmpty &&
        inputPath == null;

    final codePushClient = codePushClientWrapper.codePushClient;
    final apiBase = '${codePushClient.apiBaseUri}';
    var endpoint = endpointArg;
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
    // A path that repeats the base path ("/api/v1/apps") means the route
    // under it, since no route lives at /api/v1/api/v1.
    final basePath = codePushClient.apiBaseUri.path.replaceAll(
      RegExp(r'^/|/$'),
      '',
    );
    final relative = endpoint.startsWith('/')
        ? endpoint.substring(1)
        : endpoint;
    final repeatedBase = RegExp(
      '^${RegExp.escape(basePath)}(/|(?=[?#])|\$)',
    ).firstMatch(relative);
    if (basePath.isNotEmpty && repeatedBase != null) {
      endpoint = relative.substring(repeatedBase.end);
      stderr.writeln(
        'shorebird: Endpoints are relative to $apiBase, so requesting '
        '"/$endpoint" rather than "$endpointArg".',
      );
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

    http.StreamedResponse response;
    Uint8List responseBody;
    // The pages fetched so far with --paginate, merged into one object.
    Map<String, dynamic>? merged;
    final seenCursors = <String>{};
    while (true) {
      try {
        (response, responseBody) = await _send(
          codePushClient,
          method: method,
          url: url,
          body: body,
        );
      } on http.ClientException catch (error) {
        return _fail(error.message);
      } on SocketException catch (error) {
        return _fail(error.message);
      }
      if (!paginate || !_succeeded(response)) break;
      final page = _isJson(response) ? _decodeObject(responseBody) : null;
      if (page == null) {
        // The first page is printed as it is; a later one can't be merged.
        if (merged == null) break;
        return _fail(
          '--paginate: page ${seenCursors.length + 1} is not a JSON object',
        );
      }
      merged = merged == null ? page : _mergePages(merged, page);
      final cursor = _cursorKeys
          .map((key) => page[key])
          .firstWhere((value) => value != null, orElse: () => null);
      if (cursor == null || cursor == '') break;
      if (cursor is! String) {
        return _fail(
          '--paginate: the cursor ${jsonEncode(cursor)} is not a string, so '
          'the next page cannot be requested.',
        );
      }
      if (!seenCursors.add(cursor)) {
        return _fail(
          '--paginate: the API returned the cursor "$cursor" twice, so the '
          'pages would never end.',
        );
      }
      url = _withCursor(url, cursor);
    }
    // A single page is printed exactly as it came.
    if (merged != null && seenCursors.isNotEmpty && _succeeded(response)) {
      _cursorKeys.forEach(merged.remove);
      responseBody = utf8.encode(jsonEncode(merged));
    }

    if (response.statusCode == HttpStatus.noContent) {
      return ExitCode.success.code;
    }

    final isJson = _isJson(response);
    final indent = _output.hasTerminal ? '  ' : '';
    final succeeded = _succeeded(response);

    if (succeeded && jq != null) {
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(responseBody));
      } on FormatException {
        return _fail('--jq: the response is not JSON');
      }
      try {
        for (final value in jq.evaluate(decoded)) {
          _output.writeln(JqQuery.format(value, indent: indent));
        }
      } on JqException catch (error) {
        return _fail('--jq: ${error.message}');
      }
      return ExitCode.success.code;
    }

    final pretty = isJson && indent.isNotEmpty
        ? _prettyJson(responseBody)
        : null;
    if (pretty != null) {
      _output.writeln(pretty);
    } else {
      _output.add(responseBody);
    }
    if (succeeded) return ExitCode.success.code;
    final exitCode = _fail(
      (isJson ? _errorMessage(responseBody, response.statusCode) : null) ??
          'HTTP ${response.statusCode}',
    );
    if (fieldsMadePost && response.statusCode == HttpStatus.methodNotAllowed) {
      stderr.writeln(
        'shorebird: Fields switch the default method to POST. For a GET '
        'with query parameters, add --method GET or put them in the URL.',
      );
    }
    return exitCode;
  }

  /// Sends one request and reads its whole body.
  static Future<(http.StreamedResponse, Uint8List)> _send(
    CodePushClient codePushClient, {
    required String method,
    required String url,
    required List<int>? body,
  }) {
    final request = http.Request(method, Uri.parse(url))
      ..headers['accept'] = '*/*';
    if (body != null) {
      // Every route that takes a body takes JSON.
      request
        ..headers['content-type'] = 'application/json; charset=utf-8'
        ..bodyBytes = body;
    }
    // A write that failed may still have reached the server, so only GETs
    // are retried.
    return runScoped(
      () async {
        final response = await codePushClient.send(request);
        return (response, await response.stream.toBytes());
      },
      values: {retryFailedRequestsRef.overrideWith(() => method == 'GET')},
    );
  }

  static bool _succeeded(http.BaseResponse response) =>
      response.statusCode >= 200 && response.statusCode <= 299;

  static bool _isJson(http.BaseResponse response) => RegExp(
    r'[/+]json(;|$)',
  ).hasMatch(response.headers['content-type'] ?? '');

  static Map<String, dynamic>? _decodeObject(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Adds [page] to [merged]: lists are concatenated, and any other field
  /// keeps its value from the first page.
  static Map<String, dynamic> _mergePages(
    Map<String, dynamic> merged,
    Map<String, dynamic> page,
  ) {
    for (final MapEntry(:key, :value) in page.entries) {
      final existing = merged[key];
      if (existing is List && value is List) {
        merged[key] = [...existing, ...value];
      } else {
        merged.putIfAbsent(key, () => value);
      }
    }
    return merged;
  }

  /// [url] with its `cursor` query parameter set to [cursor].
  static String _withCursor(String url, String cursor) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            'cursor': [cursor],
          },
        )
        .toString();
  }

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
