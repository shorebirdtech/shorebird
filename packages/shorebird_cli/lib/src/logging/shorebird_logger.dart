import 'dart:io';
import 'dart:io' as io;

import 'package:cli_io/cli_io.dart';
import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/interactive_mode.dart';
import 'package:shorebird_cli/src/json_output.dart';
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
    // The interactive branch reads from real stdin; not unit-testable.
    // coverage:ignore-start
    return super.confirm(message, defaultValue: defaultValue);
    // coverage:ignore-end
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
    // The interactive branch reads from real stdin; not unit-testable.
    // coverage:ignore-start
    return super.chooseOne(
      message,
      choices: choices,
      defaultValue: defaultValue,
      display: display,
    );
    // coverage:ignore-end
  }

  @override
  String prompt(
    String? message, {
    Object? defaultValue,
    bool hidden = false,
    String? hint,
  }) {
    _failIfNonInteractive(promptText: message, hint: hint);
    // The interactive branch reads from real stdin; not unit-testable.
    // coverage:ignore-start
    return super.prompt(message, defaultValue: defaultValue, hidden: hidden);
    // coverage:ignore-end
  }

  @override
  List<String> promptAny(
    String? message, {
    String separator = ',',
    String? hint,
  }) {
    _failIfNonInteractive(promptText: message, hint: hint);
    // The interactive branch reads from real stdin; not unit-testable.
    // coverage:ignore-start
    return super.promptAny(message, separator: separator);
    // coverage:ignore-end
  }

  /// Returns a [Progress] that adapts to the current interactivity context:
  ///
  ///   * In an interactive context (TTY + no `--json`), defers to
  ///     mason_logger's animated spinner.
  ///   * Otherwise, emits a single static line on creation, and a "Done X" /
  ///     "Failed X" line on `complete`/`fail`. Output is routed to `stderr`
  ///     under `--json` so it doesn't corrupt the JSON envelope, and to
  ///     `stdout` otherwise.
  @override
  Progress progress(String message, {ProgressOptions? options}) {
    if (isInteractive) return super.progress(message, options: options);
    return _StaticProgress(
      message: message,
      sink: isJsonMode ? io.stderr : io.stdout,
      level: level,
    );
  }

  /// Throws [InteractivePromptRequiredException] when the CLI is running in
  /// a non-interactive context (no TTY on stdout/stdin, on CI, or `--json`).
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

/// {@template static_progress}
/// A non-animated [Progress] used when the CLI is running in a
/// non-interactive context (no TTY or `--json`).
///
/// Emits one line on creation and one line on completion -- no spinner,
/// no ANSI escapes, no carriage returns. Suitable for piping to logs and
/// for agentic consumers that need predictable line-oriented output.
/// {@endtemplate}
class _StaticProgress implements Progress {
  /// {@macro static_progress}
  _StaticProgress({
    required String message,
    required IOSink sink,
    required Level level,
  }) : _message = message,
       _sink = sink,
       _level = level {
    _writeln('Starting $_message...');
  }

  String _message;
  final IOSink _sink;
  final Level _level;

  void _writeln(String line) {
    if (_level.index > Level.info.index) return;
    _sink.writeln(line);
  }

  @override
  void complete([String? update]) {
    _writeln('Done ${update ?? _message}');
  }

  @override
  void fail([String? update]) {
    _writeln('Failed ${update ?? _message}');
  }

  @override
  void update(String update) {
    _message = update;
    _writeln('$_message...');
  }

  // No shorebird code path calls cancel(); required by the Progress
  // interface for compatibility with mason_logger.
  // coverage:ignore-start
  @override
  void cancel() {
    _writeln('Cancelled $_message');
  }

  // coverage:ignore-end
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
