/// Logging verbosity levels, from most verbose to least.
enum Level {
  /// Everything is logged.
  verbose,

  /// Debug-level logs (e.g. `Logger.detail`).
  debug,

  /// Standard log output (e.g. `Logger.info`).
  info,

  /// Potential problems (e.g. `Logger.warn`).
  warning,

  /// Errors (e.g. `Logger.err`).
  error,

  /// Urgent or severe problems.
  critical,

  /// Nothing is logged.
  quiet,
}

/// A function that styles a log message before it's written to the output.
typedef LogStyle = String? Function(String? message);
