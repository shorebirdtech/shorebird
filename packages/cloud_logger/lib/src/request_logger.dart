import 'dart:async';

import 'package:cloud_logger/src/cloud_logger.dart';
import 'package:cloud_logger/src/log_entry.dart';
import 'package:cloud_logger/src/logger.dart';
import 'package:shelf/shelf.dart';

/// Standard header used by
/// [Cloud Trace](https://cloud.google.com/trace/docs/setup).
const _cloudTraceContextHeader = 'x-cloud-trace-context';

/// Middleware that logs all requests.
/// If [projectId] is not null, then the requests are logged using Google Cloud
/// structured logs.
/// Otherwise, the requests are logged using the default [logRequests] API.
Middleware requestLogger([String? projectId]) {
  return projectId != null ? _cloudLogger(projectId) : logRequests();
}

/// Return [Middleware] that logs errors using Google Cloud structured logs and
/// returns the correct response.
Middleware _cloudLogger(String projectId) {
  return (handler) {
    return (request) async {
      String? traceValue;

      final traceHeader = request.headers[_cloudTraceContextHeader];
      if (traceHeader != null) {
        traceValue = 'projects/$projectId/traces/${traceHeader.split('/')[0]}';
      }

      final completer = Completer<Response>.sync();
      final currentZone = Zone.current;

      Zone.current.fork(
        zoneValues: {loggerKey: CloudLogger(currentZone, traceValue)},
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) {
            final logContentString = createErrorLogEntry(
              error,
              traceValue,
              stackTrace,
              LogSeverity.error,
            );

            parent.print(self, logContentString);

            if (completer.isCompleted) return;

            completer.complete(Response.internalServerError());
          },
          print: (self, parent, zone, line) {
            final entry = createLogEntry(traceValue, line, LogSeverity.info);
            parent.print(self, entry);
          },
        ),
      ).runGuarded(
        () async {
          final response = await handler(request);
          if (!completer.isCompleted) completer.complete(response);
        },
      );

      return completer.future;
    };
  };
}
