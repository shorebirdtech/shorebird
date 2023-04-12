import 'dart:convert';

import 'package:cloud_logger/cloud_logger.dart';
import 'package:collection/collection.dart';
import 'package:stack_trace/stack_trace.dart';

/// Create a formatted log entry.
String createLogEntry(
  String? traceValue,
  String message,
  LogSeverity severity, {
  Frame? stackFrame,
}) {
  // https://cloud.google.com/logging/docs/agent/logging/configuration#special-fields
  final logContent = {
    'message': message,
    'severity': severity,
    if (traceValue != null) 'logging.googleapis.com/trace': traceValue,
    if (stackFrame != null)
      'logging.googleapis.com/sourceLocation': _sourceLocation(stackFrame),
  };
  return json.encode(logContent);
}

/// Create a log from error information.
/// https://cloud.google.com/functions/docs/monitoring/logging#writing_structured_logs
String createErrorLogEntry(
  Object error,
  String? traceValue,
  StackTrace? stackTrace,
  LogSeverity logSeverity,
) {
  final chain = _fromStackTrace(stackTrace);
  final stackFrame = chain.traces.firstOrNull?.frames.firstOrNull;

  return createLogEntry(
    traceValue,
    '$error\n$chain'.trim(),
    logSeverity,
    stackFrame: stackFrame,
  );
}

// https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#LogEntrySourceLocation
Map<String, dynamic> _sourceLocation(Frame frame) {
  return {
    'file': frame.library,
    if (frame.line != null) 'line': frame.line.toString(),
    'function': frame.member,
  };
}

Chain _fromStackTrace(StackTrace? stackTrace) {
  return (stackTrace == null ? Chain.current() : Chain.forTrace(stackTrace))
      .foldFrames(
    (f) =>
        f.isCore ||
        f.package == 'cloud_logging' ||
        f.package == 'shelf' ||
        f.package == 'dart_frog',
    terse: true,
  );
}
