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
      ..addMultiOption(
        'header',
        abbr: 'H',
        valueHelp: 'key:value',
        splitCommas: false,
        help: 'Add a HTTP request header in key:value format.',
      )
      ..addOption(
        'input',
        valueHelp: 'file',
        help:
            'The file to use as body for the HTTP request (use "-" to read '
            'from standard input).',
      )
      ..addFlag(
        'include',
        abbr: 'i',
        negatable: false,
        help: 'Include HTTP response status line and headers in the output.',
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

The endpoint argument is a path relative to https://api.shorebird.dev/api/v1, such as "/apps" or "apps/{appId}/releases".

The placeholder "$appIdPlaceholder" in the endpoint, and in -F/--field values, is replaced with the app ID from the current project's shorebird.yaml. Pass --flavor to use a flavor's app ID.

The default HTTP request method is "GET" normally and "POST" if any fields or --input were added. Override the method with --method.

Pass one or more -f/--raw-field values in "key=value" format to add string parameters. -F/--field converts its value: "true", "false", "null" and integers become JSON values, "@<path>" reads the value from a file ("@-" from standard input), and "$appIdPlaceholder" is filled in. For "GET" requests, fields are sent as the query string; otherwise they are sent as a JSON object body. For a nested JSON body, use --input.

--input sends a file (or "-" for standard input) as the request body. Fields are then added to the query string.

The response body is printed as-is (JSON is indented when printing to a terminal). On a non-2xx response the body is still printed, an error is printed to stderr, and the command exits with status 1.

--jq takes a jq expression and prints each result: strings without quotes, other values as JSON. It supports a common subset of jq: paths (".", ".a.b", ".[]", ".[0]", "?"), "|", ",", comparisons, "and", "or", "not", object and array construction, string interpolation, and length, keys, map(f), select(f) and empty.

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

  # Use a JSON file as request body
  \$ shorebird api -X PATCH /apps/{appId}/releases/123 --input release.json''';

  @override
  Future<int> run() async {
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
    var method = (results['method'] as String).toUpperCase();
    if (!results.wasParsed('method') &&
        (params.isNotEmpty || inputPath != null)) {
      method = 'POST';
    }

    final codePushClient = codePushClientWrapper.codePushClient;
    final endpoint = _fillPlaceholders(results.rest.single);
    final path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    var url = '${codePushClient.apiBaseUri}/$path';

    List<int>? body;
    var bodyIsJson = false;
    if (inputPath != null) {
      body = await _readUserFile(inputPath, flag: '--input');
      url = _addQuery(url, params);
    } else if (params.isNotEmpty) {
      if (method == 'GET') {
        url = _addQuery(url, params);
      } else {
        body = utf8.encode(jsonEncode(params));
        bodyIsJson = true;
      }
    }

    final request = http.Request(method, Uri.parse(url));
    for (final header in results['header'] as List<String>) {
      final separator = header.indexOf(':');
      if (separator == -1) {
        usageException('header "$header" requires a value separated by ":"');
      }
      final name = header.substring(0, separator);
      final value = header.substring(separator + 1).trim();
      final existing = request.headers[name];
      request.headers[name] = existing == null ? value : '$existing, $value';
    }
    if (bodyIsJson && !request.headers.containsKey('content-type')) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
    }
    if (!request.headers.containsKey('accept')) {
      request.headers['accept'] = '*/*';
    }
    if (body != null) request.bodyBytes = body;

    final http.StreamedResponse response;
    final Uint8List responseBody;
    try {
      // A write that failed may still have reached the server, so only GETs
      // are retried.
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

    if (results['include'] as bool) {
      final reason = response.reasonPhrase;
      stdout.writeln(
        'HTTP/1.1 ${response.statusCode}'
        '${reason == null || reason.isEmpty ? '' : ' $reason'}',
      );
      final names = response.headers.keys.toList()..sort();
      for (final name in names) {
        stdout.write('$name: ${response.headers[name]}\r\n');
      }
      stdout.write('\r\n');
    }
    if (response.statusCode == HttpStatus.noContent) {
      return ExitCode.success.code;
    }

    final contentType = response.headers['content-type'] ?? '';
    final isJson = RegExp(r'[/+]json(;|$)').hasMatch(contentType);
    final indent = stdout.hasTerminal ? '  ' : '';
    final succeeded = response.statusCode >= 200 && response.statusCode <= 299;

    if (succeeded && jq != null) {
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(responseBody));
      } on FormatException {
        return _fail('--jq: the response is not JSON');
      }
      try {
        for (final value in jq.evaluate(decoded)) {
          stdout.writeln(JqQuery.format(value, indent: indent));
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
      stdout.writeln(pretty);
    } else {
      stdout.add(responseBody);
    }
    if (succeeded) return ExitCode.success.code;
    return _fail(
      (isJson ? _errorMessage(responseBody, response.statusCode) : null) ??
          'HTTP ${response.statusCode}',
    );
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
