/// An exception thrown when a process fails.
class ProcessExit implements Exception {
  /// Creates a new [ProcessExit] with the given [exitCode].
  ProcessExit(this.exitCode, {this.immediate = false});

  /// Whether the process exited immediately.
  final bool immediate;

  /// The exit code of the process.
  final int exitCode;

  /// The message associated with the exception.
  String get message => 'ProcessExit: $exitCode';

  @override
  String toString() => message;
}
