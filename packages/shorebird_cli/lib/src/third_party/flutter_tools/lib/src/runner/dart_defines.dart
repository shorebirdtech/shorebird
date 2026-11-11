// Adapted from flutter_tools' FlutterCommand (lib/src/runner/
// flutter_command.dart: DotEnvRegex, extractDartDefineConfigJsonMap,
// convertEnvFileToJsonRaw and _parseProperty) so the CLI reads a
// --dart-define-from-file file exactly as Flutter does.

import 'dart:convert';
import 'dart:io';

abstract class _DotEnvRegex {
  static final multiLineBlock = RegExp(
    r'^\s*([a-zA-Z_]+[a-zA-Z0-9_]*)\s*=\s*"""\s*(.*)$',
  );
  static final keyValue = RegExp(r'^\s*([a-zA-Z_]+[a-zA-Z0-9_]*)\s*=\s*(.*)?$');
  static final doubleQuotedValue = RegExp(r'^"(.*)"\s*(\#\s*.*)?$');
  static final singleQuotedValue = RegExp(r"^'(.*)'\s*(\#\s*.*)?$");
  static final backQuotedValue = RegExp(r'^`(.*)`\s*(\#\s*.*)?$');
  static final unquotedValue = RegExp(r'^([^#\n\s]*)\s*(?:\s*#\s*(.*))?$');
}

/// The dart-defines in [file], a `.json` object or a `.env` file, with each
/// value as the string Flutter passes as `key=value`.
///
/// Throws a [FormatException] where Flutter would refuse the file.
Map<String, String> readDartDefinesFile(File file) {
  if (!file.existsSync()) {
    throw FormatException(
      'Did not find the file passed to "--dart-define-from-file". '
      'Path: ${file.path}',
    );
  }
  final raw = file.readAsStringSync();
  final Object? decoded;
  if (raw.trim().startsWith('{')) {
    decoded = json.decode(raw);
  } else {
    decoded = _envFileEntries(raw);
  }
  if (decoded is! Map) {
    throw FormatException('${file.path} is not a JSON object.');
  }
  return {
    for (final MapEntry(:key, :value) in decoded.entries) '$key': '$value',
  };
}

Map<String, String> _envFileEntries(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !line.startsWith('#'));
  return {
    for (final line in lines) ..._parseProperty(line),
  };
}

Map<String, String> _parseProperty(String line) {
  if (_DotEnvRegex.multiLineBlock.hasMatch(line)) {
    throw FormatException('Multi-line value is not supported: $line');
  }
  final keyValueMatch = _DotEnvRegex.keyValue.firstMatch(line);
  if (keyValueMatch == null) {
    throw FormatException(
      'Unable to parse file provided for --dart-define-from-file.\n'
      'Invalid property line: $line',
    );
  }
  final key = keyValueMatch.group(1)!;
  final value = keyValueMatch.group(2) ?? '';
  for (final regex in [
    _DotEnvRegex.doubleQuotedValue,
    _DotEnvRegex.singleQuotedValue,
    _DotEnvRegex.backQuotedValue,
    _DotEnvRegex.unquotedValue,
  ]) {
    if (regex.firstMatch(value) case final match?) {
      return {key: match.group(1)!};
    }
  }
  return {key: value};
}
