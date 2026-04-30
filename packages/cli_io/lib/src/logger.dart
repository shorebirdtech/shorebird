import 'dart:io' as io;

import 'package:cli_io/src/ansi.dart';
import 'package:cli_io/src/level.dart';
import 'package:cli_io/src/progress.dart';

String? _detailStyle(String? m) => darkGray.wrap(m);
String? _infoStyle(String? m) => m;
String? _errStyle(String? m) => lightRed.wrap(m);
String? _warnStyle(String? m) => yellow.wrap(styleBold.wrap(m));
String? _successStyle(String? m) => lightGreen.wrap(m);

/// A leveled logger that writes to stdout and stderr.
///
/// Output streams honor `IOOverrides.current`, so callers wrapping work in
/// `IOOverrides.runZoned` (for example to log stdout to a file) will have
/// their overrides respected.
class Logger {
  /// Creates a [Logger] at the given [level].
  Logger({this.level = Level.info});

  /// The current log level. Messages below this level are suppressed.
  Level level;

  io.IOOverrides? get _overrides => io.IOOverrides.current;
  io.Stdout get _stdout => _overrides?.stdout ?? io.stdout;
  io.Stdout get _stderr => _overrides?.stderr ?? io.stderr;
  io.Stdin get _stdin => _overrides?.stdin ?? io.stdin;

  /// Writes [message] to stdout at info level (no styling by default).
  void info(String? message, {LogStyle? style}) {
    if (level.index > Level.info.index) return;
    final styled = (style ?? _infoStyle).call(message);
    _stdout.writeln(styled ?? message);
  }

  /// Writes [message] to stderr at error level (light red by default).
  void err(String? message, {LogStyle? style}) {
    if (level.index > Level.error.index) return;
    _stderr.writeln((style ?? _errStyle).call(message));
  }

  /// Writes [message] to stderr at warning level, prefixed with `[tag]`
  /// (yellow + bold by default).
  void warn(String? message, {String tag = 'WARN', LogStyle? style}) {
    if (level.index > Level.warning.index) return;
    final body = tag.isEmpty ? '$message' : '[$tag] $message';
    _stderr.writeln((style ?? _warnStyle).call(body));
  }

  /// Writes [message] to stdout at debug level (dark gray by default).
  void detail(String? message, {LogStyle? style}) {
    if (level.index > Level.debug.index) return;
    _stdout.writeln((style ?? _detailStyle).call(message));
  }

  /// Writes [message] to stdout at info level (light green by default).
  void success(String? message, {LogStyle? style}) {
    if (level.index > Level.info.index) return;
    _stdout.writeln((style ?? _successStyle).call(message));
  }

  /// Starts a [Progress] indicator with the given [message].
  Progress progress(String message) =>
      Progress(message: message, stdout: _stdout, level: level);

  /// Prompts the user with [message] and returns the entered response.
  ///
  /// If the user provides empty input and a [defaultValue] is given, the
  /// default is returned. Requires a terminal attached to stdout.
  String prompt(String? message, {Object? defaultValue}) {
    final hasDefault = defaultValue != null && '$defaultValue'.isNotEmpty;
    final resolvedDefault = hasDefault ? '$defaultValue' : '';
    final suffix = hasDefault ? ' ${darkGray.wrap('($resolvedDefault)')}' : '';
    final fullMessage = '$message$suffix ';
    _stdout.write(fullMessage);
    _ensureTerminalAttached();
    final input = _stdin.readLineSync()?.trim();
    final response = (input == null || input.isEmpty) ? resolvedDefault : input;
    _replacePromptLine(fullMessage, response);
    return response;
  }

  /// Prompts the user with a yes/no question.
  bool confirm(String? message, {bool defaultValue = false}) {
    final hint = defaultValue ? 'Y/n' : 'y/N';
    final suffix = ' ${darkGray.wrap('($hint)')}';
    final fullMessage = '$message$suffix ';
    _stdout.write(fullMessage);
    _ensureTerminalAttached();
    String? input;
    try {
      input = _stdin.readLineSync()?.trim();
    } on FormatException {
      // utf-8 decoding error — treat as enter, fall through to default.
      _stdout.writeln();
    }
    final response = (input == null || input.isEmpty)
        ? defaultValue
        : _parseYesNo(input) ?? defaultValue;
    _replacePromptLine(fullMessage, response ? 'Yes' : 'No');
    return response;
  }

  /// Prompts the user to choose one item from [choices] using a numbered list.
  ///
  /// Re-prompts on invalid input. If [defaultValue] is provided and the user
  /// enters an empty line, the default is returned. [display] controls how
  /// each choice is rendered; defaults to `toString`.
  T chooseOne<T extends Object?>(
    String? message, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
  }) {
    if (choices.isEmpty) {
      throw ArgumentError.value(choices, 'choices', 'must not be empty');
    }
    final render = display ?? (T value) => '$value';
    final defaultIndex = defaultValue != null
        ? choices.indexOf(defaultValue)
        : -1;
    _ensureTerminalAttached();

    while (true) {
      _stdout.writeln(message);
      for (var i = 0; i < choices.length; i++) {
        final mark = i == defaultIndex ? darkGray.wrap(' [default]') : '';
        _stdout.writeln('  ${i + 1}) ${render(choices[i])}$mark');
      }
      final hint = defaultIndex >= 0 ? ' [${defaultIndex + 1}]' : '';
      _stdout.write('Enter selection (1-${choices.length})$hint: ');
      final input = _stdin.readLineSync()?.trim();
      if ((input == null || input.isEmpty) && defaultIndex >= 0) {
        return choices[defaultIndex];
      }
      final n = int.tryParse(input ?? '');
      if (n != null && n >= 1 && n <= choices.length) {
        return choices[n - 1];
      }
      _stderr.writeln(
        lightRed.wrap(
          'Invalid selection. Please enter a number between 1 and '
          '${choices.length}.',
        ),
      );
    }
  }

  void _replacePromptLine(String fullMessage, String response) {
    final lines = fullMessage.split('\n').length - 1;
    final clear = lines > 1 ? '\x1b[A\x1b[2K\x1b[${lines}A' : '\x1b[A\x1b[2K';
    _stdout.writeln(
      '$clear$fullMessage${styleDim.wrap(lightCyan.wrap(response))}',
    );
  }

  void _ensureTerminalAttached() {
    if (!_stdout.hasTerminal) {
      throw StateError(
        'No terminal attached to stdout. '
        'Ensure a terminal is attached via stdout.hasTerminal '
        'before requesting input.',
      );
    }
  }
}

bool? _parseYesNo(String input) {
  switch (input.toLowerCase()) {
    case 'y':
    case 'yes':
    case 'yep':
    case 'yup':
    case 'yeah':
    case 'yea':
      return true;
    case 'n':
    case 'no':
    case 'nope':
      return false;
  }
  return null;
}
