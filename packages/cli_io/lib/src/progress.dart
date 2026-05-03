import 'dart:async';
import 'dart:io' as io;
import 'dart:math';

import 'package:cli_io/src/ansi.dart';
import 'package:cli_io/src/level.dart';

const _spinnerFrames = [
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⠼',
  '⠴',
  '⠦',
  '⠧',
  '⠇',
  '⠏',
];

const _frameInterval = Duration(milliseconds: 80);
const _trailing = '...';
const _padding = 15;

/// An animated progress indicator for a long-running operation.
///
/// While the operation is in flight, [Progress] writes a spinner and the
/// current [_message] to stdout. Call [complete], [fail], or [cancel] to end
/// the indicator.
class Progress {
  /// Creates a [Progress] that writes to [stdout] when the current log [level]
  /// allows info-level output. Most callers should construct progress
  /// indicators via `Logger.progress` rather than directly.
  Progress({
    required String message,
    required io.Stdout stdout,
    required Level level,
  }) : _message = message,
       _stdout = stdout,
       _level = level,
       _stopwatch = Stopwatch()..start() {
    if (!_stdout.hasTerminal) {
      // No animation when stdout isn't a terminal — just write a static line.
      final char = _spinnerFrames.first;
      _write('${lightGreen.wrap(char)} $_message$_trailing');
      return;
    }
    _timer = Timer.periodic(_frameInterval, _onTick);
  }

  final io.Stdout _stdout;
  final Level _level;
  final Stopwatch _stopwatch;

  String _message;
  Timer? _timer;
  int _index = 0;

  /// End the progress and mark it as a successful completion.
  void complete([String? update]) {
    _stopwatch.stop();
    _timer?.cancel();
    _write(
      '$_enableWrap$_clearLine${lightGreen.wrap('✓')} '
      '${update ?? _message} $_elapsed\n',
    );
  }

  /// End the progress and mark it as failed.
  void fail([String? update]) {
    _stopwatch.stop();
    _timer?.cancel();
    _write(
      '$_enableWrap$_clearLine${red.wrap('✗')} '
      '${update ?? _message} $_elapsed\n',
    );
  }

  /// Update the in-flight progress message.
  void update(String update) {
    if (_timer != null) _write(_clearLine);
    _message = update;
    _onTick(_timer);
  }

  /// Cancel the progress and remove the written line.
  void cancel() {
    _stopwatch.stop();
    _timer?.cancel();
    _write(_clearLine);
  }

  void _onTick(Timer? _) {
    _index++;
    final char = _spinnerFrames[_index % _spinnerFrames.length];
    _write(
      '$_disableWrap$_clearLine${lightGreen.wrap(char)} '
      '$_clampedMessage$_trailing $_elapsed',
    );
  }

  void _write(String content) {
    if (_level.index > Level.info.index) return;
    _stdout.write(content);
  }

  int get _terminalColumns =>
      _stdout.hasTerminal ? _stdout.terminalColumns : 80;

  String get _clampedMessage {
    final width = max(_terminalColumns - _padding, _padding);
    return _message.length > width ? _message.substring(0, width) : _message;
  }

  String get _clearLine => _stdout.hasTerminal ? '\x1b[2K\r' : '\r';

  String get _disableWrap => _stdout.hasTerminal ? '\x1b[?7l' : '';
  String get _enableWrap => _stdout.hasTerminal ? '\x1b[?7h' : '';

  String get _elapsed {
    final ms = _stopwatch.elapsed.inMilliseconds;
    final formatted = ms < 100
        ? '${ms}ms'
        : '${(ms / 1000).toStringAsFixed(1)}s';
    return '${darkGray.wrap('($formatted)')}';
  }
}
