// cspell:words subkey

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template api_command}
/// `shorebird api <endpoint>`
/// Makes an authenticated HTTP request to the Shorebird API and prints the
/// response.
/// {@endtemplate}
///
/// Modeled on `gh api` (https://cli.github.com/manual/gh_api): the flags,
/// defaults, field syntax and output match it wherever they apply, so that
/// anyone (or any agent) who knows `gh api` already knows this command.
class ApiCommand extends ShorebirdCommand {
  /// {@macro api_command}
  ApiCommand() {
    argParser
      ..addOption(
        'method',
        abbr: 'X',
        defaultsTo: 'GET',
        valueHelp: 'string',
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
      ..addFlag(
        'include',
        abbr: 'i',
        negatable: false,
        help: 'Include HTTP response status line and headers in the output.',
      )
      ..addOption(
        'input',
        valueHelp: 'file',
        help:
            'The file to use as body for the HTTP request (use "-" to read '
            'from standard input).',
      )
      ..addFlag(
        'silent',
        negatable: false,
        help: 'Do not print the response body.',
      )
      ..addFlag(
        'verbose',
        negatable: false,
        help: 'Include full HTTP request and response in the output.',
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help:
            'The product flavor whose app ID fills the {appId} placeholder '
            '(from shorebird.yaml).',
      );
  }

  /// The exit code for a request that failed: a non-2xx response or no
  /// response at all. `gh api` exits 1 in both cases.
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

The endpoint argument is a path relative to https://api.shorebird.dev/api/v1, such as "/apps" or "apps/{appId}/releases". A full URL on the same host is also accepted.

The placeholder value "$appIdPlaceholder" in the endpoint argument, and in -F/--field values, is replaced with the app ID from the current project's shorebird.yaml. Pass --flavor to use a flavor's app ID. Note that in some shells, for example PowerShell, you may need to enclose any value that contains "{...}" in quotes to prevent the shell from applying special meaning to curly braces.

The default HTTP request method is "GET" normally and "POST" if any parameters were added. Override the method with --method.

Pass one or more -f/--raw-field values in "key=value" format to add static string parameters to the request payload. To add non-string or placeholder-determined values, see -F/--field below. Note that adding request parameters will automatically switch the request method to "POST". To send the parameters as a "GET" query string instead, use --method GET.

The -F/--field flag has magic type conversion based on the format of the value:

- literal values "true", "false", "null", and integer numbers get converted to appropriate JSON types;
- the placeholder value "$appIdPlaceholder" gets populated with the app ID of the current project;
- if the value starts with "@", the rest of the value is interpreted as a filename to read the value from. Pass "-" to read from standard input.

To pass nested parameters in the request payload, use "key[subkey]=value" syntax when declaring fields. To pass nested values as arrays, declare multiple fields with the syntax "key[]=value1", "key[]=value2". To pass an empty array, use "key[]" without a value.

To pass pre-constructed JSON or payloads in other formats, a request body may be read from file specified by --input. Use "-" to read from standard input. When passing the request body this way, any parameters specified via field flags are added to the query string of the endpoint URL.

Requests are authenticated as your "shorebird login" session, or with the API key in the SHOREBIRD_TOKEN environment variable.

The API reference is at https://api.shorebird.dev/openapi.json, and guides are at https://docs.shorebird.dev/account/api/. The API is published, but it has no compatibility guarantee yet: routes and response shapes may change.

Examples:
  # List the apps you have access to
  \$ shorebird api /apps

  # List the releases of the app in the current project
  \$ shorebird api /apps/{appId}/releases

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
    final silent = results['silent'] as bool;
    final verbose = results['verbose'] as bool;
    if (silent && verbose) {
      usageException('Only one of --silent or --verbose may be used.');
    }

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return reportPreconditionFailure(error);
    }

    final params = await _parseFields();
    final inputPath = results['input'] as String?;
    var method = (results['method'] as String).toUpperCase();
    if (!results.wasParsed('method') &&
        (params.isNotEmpty || inputPath != null)) {
      method = 'POST';
    }

    final codePushClient = codePushClientWrapper.codePushClient;
    var url = _resolveUrl(
      _fillPlaceholders(results.rest.single),
      apiBaseUri: codePushClient.apiBaseUri,
    );

    List<int>? body;
    var bodyIsJson = false;
    if (inputPath != null) {
      body = await _readUserFile(inputPath, flag: '--input');
      url = addQuery(url, params);
    } else if (params.isNotEmpty) {
      if (method == 'GET') {
        url = addQuery(url, params);
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

    final startedAt = DateTime.now();
    final http.StreamedResponse response;
    final Uint8List responseBody;
    try {
      response = await codePushClient.send(request);
      responseBody = await response.stream.toBytes();
    } on http.ClientException catch (error) {
      stderr.writeln('shorebird: ${error.message}');
      return requestFailedExitCode;
    } on SocketException catch (error) {
      stderr.writeln('shorebird: ${error.message}');
      return requestFailedExitCode;
    }
    final elapsed = DateTime.now().difference(startedAt);

    final contentType = response.headers['content-type'] ?? '';
    final isJson = RegExp(r'[/+]json(;|$)').hasMatch(contentType);
    final prettyPrint = isJson && stdout.hasTerminal;

    if (verbose) {
      _writeVerbose(
        request: request,
        response: response,
        responseBody: responseBody,
        prettyPrint: prettyPrint,
        startedAt: startedAt,
        elapsed: elapsed,
      );
    } else {
      if (results['include'] as bool) _writeStatusAndHeaders(response);
      if (!silent && response.statusCode != HttpStatus.noContent) {
        _writeBody(responseBody, prettyPrint: prettyPrint);
      }
    }

    if (response.statusCode >= 200 && response.statusCode <= 299) {
      return ExitCode.success.code;
    }
    String? serverError;
    if (isJson && response.statusCode >= 400 && method != 'HEAD') {
      serverError = _errorMessage(responseBody, response.statusCode);
    }
    stderr.writeln(
      'shorebird: ${serverError ?? 'HTTP ${response.statusCode}'}',
    );
    return requestFailedExitCode;
  }

  String? _appId;

  /// The app ID of the current project, read the first time a placeholder
  /// needs it.
  String get _currentAppId => _appId ??= _resolveAppId();

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

  /// Replaces each [appIdPlaceholder] in [value] with the current project's
  /// app ID, as `gh api` replaces `{owner}` and `{repo}`. Other `{...}`
  /// sequences are left alone.
  String _fillPlaceholders(String value) => value.contains(appIdPlaceholder)
      ? value.replaceAll(appIdPlaceholder, _currentAppId)
      : value;

  /// The request URL for [endpoint]: a path relative to [apiBaseUri], or a
  /// full URL on the same host.
  String _resolveUrl(String endpoint, {required Uri apiBaseUri}) {
    if (endpoint.contains('://')) {
      final uri = Uri.tryParse(endpoint);
      if (uri == null || uri.origin != apiBaseUri.origin) {
        usageException(
          '"$endpoint" is not on the Shorebird API host. shorebird api only '
          'sends requests (and your credentials) to ${apiBaseUri.origin}.',
        );
      }
      return endpoint;
    }
    final path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return '$apiBaseUri/$path';
  }

  /// Parses the -f/--raw-field and -F/--field values into request
  /// parameters, following `gh api`'s `parseFields`.
  Future<Map<String, Object?>> _parseFields() async {
    final params = <String, Object?>{};
    for (final field in results['raw-field'] as List<String>) {
      await _parseField(params, field, isMagic: false);
    }
    for (final field in results['field'] as List<String>) {
      await _parseField(params, field, isMagic: true);
    }
    return params;
  }

  Future<void> _parseField(
    Map<String, Object?> params,
    String field, {
    required bool isMagic,
  }) async {
    var valueIndex = 0;
    final keyStack = <String>[];
    var keyStartAt = 0;
    for (var i = 0; i < field.length; i++) {
      final char = field[i];
      if (char == '[') {
        if (keyStartAt == 0) keyStack.add(field.substring(0, i));
        keyStartAt = i + 1;
      } else if (char == ']') {
        keyStack.add(field.substring(keyStartAt, i));
      } else if (char == '=') {
        if (keyStartAt == 0) keyStack.add(field.substring(0, i));
        valueIndex = i + 1;
        break;
      }
    }

    if (keyStack.isEmpty) usageException('invalid key: "$field"');

    var key = field;
    Object? value;
    if (valueIndex == 0) {
      if (keyStack.last.isNotEmpty) {
        usageException(
          'field "$key" requires a value separated by an "=" sign',
        );
      }
    } else {
      key = field.substring(0, valueIndex - 1);
      value = field.substring(valueIndex);
    }

    if (isMagic && value != null) {
      value = await _magicFieldValue(value as String, key: key);
    }

    var destination = params;
    var isArray = false;
    var subKey = '';
    for (final k in keyStack) {
      if (k.isEmpty) {
        isArray = true;
        continue;
      }
      if (subKey.isNotEmpty) {
        if (isArray) {
          destination = _addParamsList(destination, subKey, k);
          isArray = false;
        } else {
          destination = _addParamsMap(destination, subKey);
        }
      }
      subKey = k;
    }

    if (isArray) {
      if (value == null) {
        destination[subKey] = <Object?>[];
      } else {
        final existing = destination[subKey];
        if (existing == null && !destination.containsKey(subKey)) {
          destination[subKey] = <Object?>[value];
        } else if (existing is List<Object?>) {
          existing.add(value);
        } else {
          usageException(
            'expected array type under "$subKey", got ${_typeName(existing)}',
          );
        }
      }
    } else {
      if (destination.containsKey(subKey)) {
        usageException('unexpected override existing field under "$subKey"');
      }
      destination[subKey] = value;
    }
  }

  Map<String, Object?> _addParamsMap(Map<String, Object?> map, String key) {
    if (map.containsKey(key)) {
      final existing = map[key];
      if (existing is Map<String, Object?>) return existing;
      usageException(
        'expected map type under "$key", got ${_typeName(existing)}',
      );
    }
    final newMap = <String, Object?>{};
    map[key] = newMap;
    return newMap;
  }

  Map<String, Object?> _addParamsList(
    Map<String, Object?> map,
    String previousKey,
    String newKey,
  ) {
    if (map.containsKey(previousKey)) {
      final existing = map[previousKey];
      if (existing is! List<Object?>) {
        usageException(
          'expected array type under "$previousKey", got '
          '${_typeName(existing)}',
        );
      }
      if (existing.isNotEmpty) {
        final lastItem = existing.last;
        if (lastItem is Map<String, Object?> &&
            (!lastItem.containsKey(newKey) || lastItem[newKey] is List)) {
          return lastItem;
        }
      }
      final newMap = <String, Object?>{};
      existing.add(newMap);
      return newMap;
    }
    final newMap = <String, Object?>{};
    map[previousKey] = <Object?>[newMap];
    return newMap;
  }

  static String _typeName(Object? value) => switch (value) {
    null => 'null',
    String() => 'string',
    int() => 'integer',
    bool() => 'boolean',
    List() => 'array',
    _ => 'map',
  };

  /// Converts a -F/--field value: `@file` and `@-` read a file or stdin,
  /// integers, `true`, `false` and `null` become JSON values, and anything
  /// else is a string with placeholders filled. Follows `gh api`'s
  /// `magicFieldValue`.
  Future<Object?> _magicFieldValue(String value, {required String key}) async {
    if (value.startsWith('@')) {
      final bytes = await _readUserFile(value.substring(1), flag: '"$key"');
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

  void _writeStatusAndHeaders(http.StreamedResponse response) {
    stdout
      ..writeln('HTTP/1.1 ${_status(response)}')
      ..write(_formatHeaders(response.headers, lineEnd: '\r\n'))
      ..write('\r\n');
  }

  void _writeBody(List<int> body, {required bool prettyPrint}) {
    if (prettyPrint) {
      final pretty = _prettyJson(body);
      if (pretty != null) {
        stdout.writeln(pretty);
        return;
      }
    }
    stdout.add(body);
  }

  /// Writes the request and response the way `gh api --verbose` does: to
  /// stdout, request lines prefixed with `>`, response lines with `<`, and
  /// the credential in the Authorization header masked.
  void _writeVerbose({
    required http.Request request,
    required http.StreamedResponse response,
    required List<int> responseBody,
    required bool prettyPrint,
    required DateTime startedAt,
    required Duration elapsed,
  }) {
    final url = request.url;
    final target = url.hasQuery ? '${url.path}?${url.query}' : url.path;
    final requestHeaders = {
      for (final MapEntry(:key, :value) in request.headers.entries)
        key: key.toLowerCase() == 'authorization'
            ? redactAuthorization(value)
            : value,
    };
    stdout
      ..writeln('* Request at $startedAt')
      ..writeln('* Request to $url')
      ..writeln('> ${request.method} $target HTTP/1.1')
      ..writeln('> Host: ${url.authority}')
      ..write(_formatHeaders(requestHeaders, prefix: '> '))
      ..writeln();
    if (request.bodyBytes.isNotEmpty) {
      stdout
        ..writeln(utf8.decode(request.bodyBytes, allowMalformed: true))
        ..writeln();
    }
    stdout
      ..writeln('< HTTP/1.1 ${_status(response)}')
      ..write(_formatHeaders(response.headers, prefix: '< '))
      ..writeln();
    if (responseBody.isNotEmpty) {
      _writeBody(responseBody, prettyPrint: prettyPrint);
      stdout.writeln();
    }
    stdout.writeln('* Request took ${elapsed.inMilliseconds}ms');
  }

  static String _status(http.BaseResponse response) {
    final reason = response.reasonPhrase;
    return reason == null || reason.isEmpty
        ? '${response.statusCode}'
        : '${response.statusCode} $reason';
  }

  /// [headers] sorted by name, one per line, with names in canonical case
  /// (`Content-Type`), as Go's `net/http` prints them.
  static String _formatHeaders(
    Map<String, String> headers, {
    String prefix = '',
    String lineEnd = '\n',
  }) {
    final names = headers.keys.toList()..sort((a, b) => a.compareTo(b));
    final buffer = StringBuffer();
    for (final name in names) {
      buffer.write(
        '$prefix${canonicalHeaderName(name)}: ${headers[name]}$lineEnd',
      );
    }
    return buffer.toString();
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

/// [value] of an Authorization header with the credential masked, keeping
/// the scheme (`Bearer ████████████████████`).
String redactAuthorization(String value) {
  const mask = '████████████████████';
  final space = value.indexOf(' ');
  return space == -1 ? mask : '${value.substring(0, space)} $mask';
}

/// [name] in canonical header case: the first letter and each letter after a
/// hyphen upper case, the rest lower case (`content-type` becomes
/// `Content-Type`).
String canonicalHeaderName(String name) => name
    .split('-')
    .map(
      (part) => part.isEmpty
          ? part
          : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
    )
    .join('-');

/// Appends [params] to [url] as a query string, following `gh api`'s
/// `addQuery`: arrays repeat the key with a `[]` suffix, nested maps
/// contribute their own keys, and `null` becomes an empty value. Keys are
/// sorted, as Go's `url.Values.Encode` sorts them.
String addQuery(String url, Map<String, Object?> params) {
  if (params.isEmpty) return url;
  final query = <String, List<String>>{};
  void add(String key, Object? value) {
    switch (value) {
      case null:
        (query[key] ??= []).add('');
      case String() || int() || bool():
        (query[key] ??= []).add('$value');
      case Map<String, Object?>():
        for (final MapEntry(key: subKey, :value) in value.entries) {
          add(subKey, value);
        }
      case List<Object?>():
        for (final entry in value) {
          add('$key[]', entry);
        }
    }
  }

  add('', params);
  final keys = query.keys.toList()..sort();
  final encoded = [
    for (final key in keys)
      for (final value in query[key]!)
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
  ].join('&');
  final separator = url.contains('?') ? '&' : '?';
  return '$url$separator$encoded';
}
