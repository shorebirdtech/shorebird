import 'dart:io';

import 'package:clock/clock.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// A reference to a [Logger] instance.
final loggerRef = create(ShorebirdLogger.new);

/// The [Logger] instance available in the current zone.
ShorebirdLogger get logger => read(loggerRef);

const _logFileName = 'shorebird.log';

/// Where logs are written for the current Shorebird CLI run. A new file will
/// be created for every run of the Shorebird CLI, and will have the name
/// `timestamp_shorebird.log`.
final File currentRunLogFile = (() {
  final timestamp = clock.now().millisecondsSinceEpoch;
  final file = File(
    p.join(shorebirdEnv.logsDirectory.path, '${timestamp}_$_logFileName'),
  );

  if (!file.existsSync()) {
    file.createSync(recursive: true);
  }

  return file;
})();

/// {@template shorebird_logger}
/// A [Logger] that writes verbose output to a per-run log file and fails
/// fast on interactive prompts (`chooseOne`/`confirm`/`prompt`/`promptAny`)
/// when the CLI is running in a non-interactive context.
/// {@endtemplate}
class ShorebirdLogger extends Logger {
  /// {@macro shorebird_logger}
  ShorebirdLogger({super.level});

  @override
  void detail(String? message, {LogStyle? style}) {
    super.detail(message, style: style);
    if (level.index > Level.debug.index) {
      // We only need to write the message to the log file if this will not
      // be written to stdout. If it is written to stdout, [LoggingStdout] will
      // written to the log file.
      writeToLogFile(message ?? '', logFile: currentRunLogFile);
    }
  }

  @override
  bool confirm(String? message, {bool defaultValue = false, String? hint}) {
    _failIfNonInteractive(promptText: message, hint: hint);
    return super.confirm(message, defaultValue: defaultValue);
  }

  @override
  T chooseOne<T extends Object?>(
    String? message, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
    String? hint,
  }) {
    _failIfNonInteractive(promptText: message, hint: hint);
    return super.chooseOne(
      message,
      choices: choices,
      defaultValue: defaultValue,
      display: display,
    );
  }

  @override
  String prompt(
    String? message, {
    Object? defaultValue,
    bool hidden = false,
    String? hint,
  }) {
    _failIfNonInteractive(promptText: message, hint: hint);
    return super.prompt(message, defaultValue: defaultValue, hidden: hidden);
  }

  @override
  List<String> promptAny(
    String? message, {
    String separator = ',',
    String? hint,
  }) {
    _failIfNonInteractive(promptText: message, hint: hint);
    return super.promptAny(message, separator: separator);
  }

  /// Throws [InteractivePromptRequiredException] when the CLI is running in
  /// a non-interactive context (no TTY on stdout/stdin, on CI, `--json`, or
  /// `--no-input`).
  ///
  /// Used by all interactive prompt methods to fail fast with an actionable
  /// error rather than blocking on stdin or producing garbled output.
  void _failIfNonInteractive({String? promptText, String? hint}) {
    if (isInteractive && shorebirdEnv.canAcceptUserInput) return;
    throw InteractivePromptRequiredException(
      promptText: promptText ?? '(no prompt text)',
      hint: hint ?? defaultInteractivePromptHint,
    );
  }
}

/// Writes the given [message] to the [logFile] on its own line, prefixed with
/// the current timestamp.
void writeToLogFile(Object? message, {required File logFile}) {
  if (message == null) {
    return;
  }

  final timestampString = DateTime.now().toIso8601String();
  final messageString = message.toString();
  logFile.writeAsStringSync(
    '$timestampString $messageString\n',
    mode: FileMode.append,
  );
}
