import 'dart:io';

import 'package:shorebird_build_trace/src/build_tracer.dart';
import 'package:shorebird_build_trace/src/process_id.dart';

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

/// Sync variant of [runSubprocess] for callers that can't go async —
/// e.g., factory constructors. Since [Process.runSync] never exposes
/// the child's pid, the span is recorded on the caller's process/
/// thread rather than on its own Perfetto row.
///
/// [pid] defaults to [currentProcessId]; [tid] defaults to 1 (the
/// main aot_tools / flutter_tool thread). Callers with their own
/// thread layout can override.
ProcessResult runSubprocessSync(
  String executable,
  List<String> arguments, {
  int? pid,
  int tid = 1,
}) {
  final tracer = BuildTracer.current;
  if (tracer == null) {
    return Process.runSync(executable, arguments);
  }
  return tracer.timeSubprocess(
    executable: executable,
    arguments: arguments,
    pid: pid ?? currentProcessId(),
    tid: tid,
    runner: () => Process.runSync(executable, arguments),
  );
}
