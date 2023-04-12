import 'dart:async';

import 'package:cloud_logger/cloud_logger.dart';
import 'package:cloud_logger/src/log_entry.dart';

/// {@template cloud_logger}
/// A [Logger] that complies with Google Cloud structured logging.
/// {@endtemplate}
class CloudLogger extends Logger {
  /// {@macro cloud_logger}
  const CloudLogger(this._zone, this._traceId);

  final Zone _zone;
  final String? _traceId;

  @override
  void log(Object message, LogSeverity severity) {
    _zone.print(createLogEntry(_traceId, '$message', severity));
  }
}
