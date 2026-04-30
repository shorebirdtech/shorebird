import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/version.dart';

/// A reference to whether JSON output mode is active.
final isJsonModeRef = create(() => false);

/// Whether JSON output mode is active in the current zone.
bool get isJsonMode => read(isJsonModeRef);

/// Builds the subcommand name from [ArgResults] by walking the command chain
/// (e.g. "doctor" for `shorebird doctor`, "patch ios" for `shorebird patch ios`).
///
/// Returns `null` when no subcommand was recognized (bare `shorebird` invocation).
String? commandNameFromResults(ArgResults topLevelResults) {
  final parts = <String>[];
  var command = topLevelResults.command;
  while (command != null) {
    final name = command.name;
    if (name != null) parts.add(name);
    command = command.command;
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// The status field in a JSON output envelope.
enum JsonStatus {
  /// The command completed successfully.
  success,

  /// The command failed.
  error,
}

/// Machine-readable error codes for JSON output.
enum JsonErrorCode {
  /// A process exited with a non-zero exit code.
  processExit('process_exit'),

  /// The CLI was invoked with invalid arguments.
  usageError('usage_error'),

  /// An unhandled exception occurred.
  softwareError('software_error'),

  /// A network fetch or data retrieval failed.
  fetchFailed('fetch_failed'),

  /// The CLI required interactive input but no terminal/stdin was available
  /// (or the user passed `--json`).
  interactivePromptRequired('interactive_prompt_required');

  const JsonErrorCode(this.code);

  /// The wire-format string (e.g. "process_exit").
  final String code;
}

/// {@template json_meta}
/// Metadata included in every JSON output envelope.
/// {@endtemplate}
class JsonMeta {
  /// {@macro json_meta}
  const JsonMeta({required this.version, required this.command});

  /// The CLI version that produced this output.
  final String version;

  /// The full command name (e.g. "doctor").
  final String command;

  /// Serializes this metadata to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'version': version,
    'command': command,
  };
}

/// {@template json_error}
/// Structured error information for JSON output.
/// {@endtemplate}
class JsonError {
  /// {@macro json_error}
  const JsonError({required this.code, required this.message, this.hint});

  /// A machine-readable error code.
  final JsonErrorCode code;

  /// A human-readable error description.
  final String message;

  /// An optional actionable recovery step
  /// (e.g. "Run: shorebird login:ci").
  final String? hint;

  /// Serializes this error to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'code': code.code,
    'message': message,
    if (hint != null) 'hint': hint,
  };
}

/// {@template json_result}
/// Structured result envelope for `--json` CLI output.
///
/// Every JSON response follows this shape:
/// ```json
/// {
///   "status": "success" | "error",
///   "data": { ... },           // present on success
///   "error": { ... },          // present on error
///   "meta": { "version": "...", "command": "..." }
/// }
/// ```
/// {@endtemplate}
class JsonResult {
  const JsonResult._({required this.toJson});

  /// Creates a success result with the given [data].
  ///
  /// The `command` is the full command name (e.g. "doctor") and is
  /// injected into the `meta` block automatically.
  factory JsonResult.success({
    required Map<String, dynamic> data,
    required String command,
  }) {
    final meta = JsonMeta(version: packageVersion, command: command);
    return JsonResult._(
      toJson: () => {
        'status': JsonStatus.success.name,
        'data': data,
        'meta': meta.toJson(),
      },
    );
  }

  /// Creates an error result.
  ///
  /// [code] is a machine-readable [JsonErrorCode].
  /// `message` is a human-readable description.
  /// `hint` is an optional actionable recovery step.
  /// `command` is injected into the `meta` block automatically.
  factory JsonResult.error({
    required JsonErrorCode code,
    required String message,
    required String command,
    String? hint,
  }) {
    final error = JsonError(code: code, message: message, hint: hint);
    final meta = JsonMeta(version: packageVersion, command: command);
    return JsonResult._(
      toJson: () => {
        'status': JsonStatus.error.name,
        'error': error.toJson(),
        'meta': meta.toJson(),
      },
    );
  }

  /// Serializes this result to a JSON-compatible map.
  final Map<String, dynamic> Function() toJson;

  /// Writes this result to stdout as a single JSON line.
  void write() {
    io.stdout.writeln(jsonEncode(toJson()));
  }
}
