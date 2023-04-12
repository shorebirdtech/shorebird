import 'dart:async';

/// Used to represent the [Logger] in [Zone] values.
final loggerKey = Object();

/// {@template logger}
/// Log messages with an associated severity level.
///
/// https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#logseverity
/// {@endtemplate}
abstract class Logger {
  /// {@macro logger}
  const Logger();

  /// Log a message with the given severity.
  void log(Object message, LogSeverity severity);

  /// Log a message with debug or trace information..
  void debug(Object message) => log(message, LogSeverity.debug);

  /// Log a message with routine information.
  void info(Object message) => log(message, LogSeverity.info);

  /// Log a message with normal but significant events.
  void notice(Object message) => log(message, LogSeverity.notice);

  /// Log a message with events that might cause problems.
  void warning(Object message) => log(message, LogSeverity.warning);

  /// Log a message with events that are likely to cause problems.
  void error(Object message) => log(message, LogSeverity.error);

  /// Log a message with events that will cause severe problems or outages.
  void critical(Object message) => log(message, LogSeverity.critical);

  /// Log a message with events that require immediate action.
  void alert(Object message) => log(message, LogSeverity.alert);

  /// Log a message with events that render the system unusable.
  void emergency(Object message) => log(message, LogSeverity.emergency);
}

/// See https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#logseverity
enum LogSeverity implements Comparable<LogSeverity> {
  /// The log entry has no assigned severity level.
  defaultSeverity._(0, 'DEFAULT'),

  /// Debug or trace information.
  debug._(100, 'DEBUG'),

  /// Routine information, such as ongoing status or performance.
  info._(200, 'INFO'),

  /// Normal but significant events, such as start up, shut down.
  notice._(300, 'NOTICE'),

  /// Events that might cause problems.
  warning._(400, 'WARNING'),

  /// Events that are likely to cause problems.
  error._(500, 'ERROR'),

  /// Events that will cause severe problems or outages.
  critical._(600, 'CRITICAL'),

  /// Events that require immediate action.
  alert._(700, 'ALERT'),

  /// Events that render the system unusable.
  emergency._(800, 'EMERGENCY');

  const LogSeverity._(this.value, this.name);

  /// The severity value.
  final int value;

  /// The severity name.
  final String name;

  @override
  int compareTo(LogSeverity other) => value.compareTo(other.value);

  @override
  String toString() => 'LogSeverity $name ($value)';

  /// Convert a [LogSeverity] to a JSON string.
  String toJson() => name;
}

/// Returns the [Logger] for the current [Zone].
Logger get logger => Zone.current[loggerKey] as Logger? ?? const _BasicLogger();

class _BasicLogger extends Logger {
  const _BasicLogger();

  @override
  void log(Object message, LogSeverity severity) {
    final prefix =
        severity == LogSeverity.defaultSeverity ? '' : '[${severity.name}]: ';
    // ignore: avoid_print
    print('$prefix$message');
  }
}
