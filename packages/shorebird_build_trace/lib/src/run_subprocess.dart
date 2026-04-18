import 'dart:io';

import 'package:shorebird_build_trace/src/build_tracer.dart';

/// Runs [executable] with [arguments] via [Process.start], tracing the
/// subprocess on its own OS pid when a [BuildTracer] is installed via
/// [BuildTracer.runAsync]. Returns a [ProcessResult] with the same
/// shape as [Process.run] would, so callers can swap `Process.run` for
/// this helper without changing surrounding code.
///
/// Callers never reference [BuildTracer.current] directly; this helper
/// is the single place that branches on "is tracing on?".
Future<ProcessResult> runSubprocess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final tracer = BuildTracer.current;
  if (tracer == null) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
  return tracer.startAndTraceSubprocess(
    executable: executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
