import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Reports an error from [command] (its full name, such as "release ios") in
/// whichever output mode is active.
///
/// With `--json`, writes an error envelope carrying [code], [message] and
/// [hint]. Otherwise logs [message] as an error and [hint], if any, as info.
/// Both modes report the same [message].
void reportCommandError({
  required String command,
  required String message,
  String? hint,
  JsonErrorCode code = JsonErrorCode.usageError,
}) {
  if (isJsonMode) {
    JsonResult.error(
      code: code,
      message: message,
      hint: hint,
      command: command,
    ).write();
  } else {
    logger.err(message);
    if (hint != null) logger.info(hint);
  }
}

/// {@template command_error}
/// A [ProcessExit] carrying an error to report: one line saying what's
/// wrong ([message]) and, when there is one, what to do about it ([hint],
/// such as "Run: shorebird release ios --no-codesign").
///
/// Thrown by code that runs on a command's behalf but isn't the command
/// itself (a releaser, a patcher), which has no command to report through.
/// Nothing is logged where it is thrown: the command runner reports it with
/// [reportCommandError], as `ShorebirdCommand.reportError` does, so it reads
/// the same as a command's own errors, in `--json` mode too.
/// {@endtemplate}
class CommandError extends ProcessExit {
  /// {@macro command_error}
  ///
  /// [code] defaults to [JsonErrorCode.usageError] when [exitCode] is
  /// [ExitCode.usage] and [JsonErrorCode.processExit] otherwise.
  CommandError({
    required this.message,
    this.hint,
    ExitCode exitCode = ExitCode.usage,
    JsonErrorCode? code,
  }) : code =
           code ??
           (exitCode == ExitCode.usage
               ? JsonErrorCode.usageError
               : JsonErrorCode.processExit),
       super(exitCode.code);

  /// What's wrong, in one line.
  @override
  final String message;

  /// What to do about it, if there is something to do.
  final String? hint;

  /// The machine-readable error code reported with `--json`.
  final JsonErrorCode code;

  /// Reports this error for [command] with [reportCommandError].
  void report({required String command}) => reportCommandError(
    command: command,
    message: message,
    hint: hint,
    code: code,
  );
}
