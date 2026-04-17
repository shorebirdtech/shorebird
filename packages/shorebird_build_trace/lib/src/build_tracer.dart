import 'dart:convert';
import 'dart:io';

import 'package:shorebird_build_trace/src/build_trace_event.dart';
import 'package:shorebird_build_trace/src/process_id.dart';

/// Shorebird convention: all events from one producer share a single pid
/// (the OS pid of the producing process), plus `process_name` metadata
/// naming it. Callers pick their own tid numbering within their pid.
///
/// [BuildTracer] buffers events and writes them as Chrome Trace Event
/// Format JSON. Events mix complete spans (`ph: "X"`), metadata
/// (`ph: "M"`), and flow events (`ph: "s"` / `"f"`) in a single list so
/// Perfetto sees a coherent trace when the file is merged by a parent
/// process.
///
/// Lookalike helpers on this class match the shape of
/// `dart:developer`'s `Timeline`:
/// * [trace] / [traceAsync] → `Timeline.timeSync` / `timeSync` async.
/// * [timeSubprocess] / [timeSubprocessAsync] → scoped wrappers around
///   `Process.runSync` / `Process.start` that emit a subprocess span.
/// * [recordNetworkSpan] → HTTP-request span with the standard args
///   shape (method/host/status/error).
///
/// See also [PhaseTracker] for the `transitionTo(nextPhase)` pattern
/// used when parsing a subprocess's verbose output.
class BuildTracer {
  /// The tracer for the in-progress build, if any. Set by the producer's
  /// entry point when tracing is enabled so deep layers (network, subprocess
  /// wrappers) can record spans without plumbing a parameter through every
  /// signature. Null when tracing is off.
  static BuildTracer? current;

  /// Raw JSON maps: complete spans (ph:"X"), metadata (ph:"M"), and flow
  /// events (ph:"s"/"f") share the buffer so each consumer can emit any
  /// of them without a stricter typed API.
  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];

  /// Number of events recorded so far. Used mainly by tests.
  int get eventCount => _events.length;

  /// Unmodifiable view of the raw event maps, for tests that need to
  /// inspect individual spans without round-tripping through a file.
  List<Map<String, Object?>> get events => List.unmodifiable(_events);

  /// Adds a completed span (`ph: "X"`).
  void addCompleteEvent({
    required String name,
    required String cat,
    required int pid,
    required int tid,
    required int startMicros,
    required int endMicros,
    Map<String, Object?>? args,
  }) {
    _events.add(
      BuildTraceEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        ts: startMicros,
        dur: endMicros - startMicros,
        args: args,
      ).toJson(),
    );
  }

  /// Emits a `process_name` metadata event so Perfetto shows [name] in
  /// place of the bare pid number.
  void addProcessNameMetadata({required int pid, required String name}) {
    _events.add(<String, Object?>{
      'name': 'process_name',
      'ph': 'M',
      'pid': pid,
      'args': <String, Object?>{'name': name},
    });
  }

  /// Emits a `thread_name` metadata event so Perfetto shows [name] on the
  /// row for ([pid], [tid]).
  void addThreadNameMetadata({
    required int pid,
    required int tid,
    required String name,
  }) {
    _events.add(<String, Object?>{
      'name': 'thread_name',
      'ph': 'M',
      'pid': pid,
      'tid': tid,
      'args': <String, Object?>{'name': name},
    });
  }

  /// Emits a flow-start event (`ph: "s"`) tying the enclosing span at
  /// ([pid], [tid], [atMicros]) to a flow-end event a spawned child will
  /// emit with the same [id]. Shorebird convention uses the child's pid
  /// as the flow id so spawner and spawnee agree on the id without
  /// passing it through env vars.
  void addFlowStart({
    required int id,
    required int pid,
    required int tid,
    required int atMicros,
  }) {
    _events.add(<String, Object?>{
      'ph': 's',
      'name': 'spawn',
      'cat': 'flow',
      'id': id,
      'ts': atMicros,
      'pid': pid,
      'tid': tid,
      'bp': 'e',
    });
  }

  /// Emits a flow-end event (`ph: "f"`) tying this producer's span to a
  /// flow the parent process started with `ph: "s"` under the same [id].
  void addFlowEnd({
    required int id,
    required int pid,
    required int tid,
    required int atMicros,
  }) {
    _events.add(<String, Object?>{
      'ph': 'f',
      'name': 'spawn',
      'cat': 'flow',
      'id': id,
      'ts': atMicros,
      'pid': pid,
      'tid': tid,
      'bp': 'e',
    });
  }

  /// Runs [body], times it, and emits a complete span describing it.
  /// Matches `dart:developer`'s `Timeline.timeSync<T>()`. Exceptions
  /// propagate; the span is still recorded via a try/finally.
  T trace<T>({
    required String name,
    required String cat,
    required int pid,
    required int tid,
    required T Function() body,
    Map<String, Object?>? args,
  }) {
    final startMicros = DateTime.now().microsecondsSinceEpoch;
    try {
      return body();
    } finally {
      addCompleteEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        startMicros: startMicros,
        endMicros: DateTime.now().microsecondsSinceEpoch,
        args: args,
      );
    }
  }

  /// Async variant of [trace]. Span is recorded once [body] completes
  /// (or throws).
  Future<T> traceAsync<T>({
    required String name,
    required String cat,
    required int pid,
    required int tid,
    required Future<T> Function() body,
    Map<String, Object?>? args,
  }) async {
    final startMicros = DateTime.now().microsecondsSinceEpoch;
    try {
      return await body();
    } finally {
      addCompleteEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        startMicros: startMicros,
        endMicros: DateTime.now().microsecondsSinceEpoch,
        args: args,
      );
    }
  }

  /// Adds a span describing a subprocess invocation whose timing the
  /// caller already measured. Span name is the [executable] basename;
  /// the full argv lands in `args.argv`. Prefer [timeSubprocess] /
  /// [timeSubprocessAsync] when you're *about* to run the process;
  /// this helper is for call sites that already have start/end micros
  /// (e.g. an existing stopwatch-around-run pattern).
  void addSubprocessEvent({
    required String executable,
    required List<String> arguments,
    required int pid,
    required int tid,
    required int startMicros,
    required int endMicros,
  }) {
    addCompleteEvent(
      name: _basename(executable),
      cat: 'subprocess',
      pid: pid,
      tid: tid,
      startMicros: startMicros,
      endMicros: endMicros,
      args: <String, Object?>{'argv': arguments},
    );
  }

  /// Emits a span that covers a subprocess invocation. [runner] should
  /// invoke [Process.runSync] (or equivalent) with [executable] and
  /// [arguments]; the span wraps it with start/end micros, and the
  /// executable basename + full argv end up in the Perfetto span pane.
  ProcessResult timeSubprocess({
    required String executable,
    required List<String> arguments,
    required int pid,
    required int tid,
    required ProcessResult Function() runner,
  }) {
    final startMicros = DateTime.now().microsecondsSinceEpoch;
    final result = runner();
    addCompleteEvent(
      name: _basename(executable),
      cat: 'subprocess',
      pid: pid,
      tid: tid,
      startMicros: startMicros,
      endMicros: DateTime.now().microsecondsSinceEpoch,
      args: <String, Object?>{'argv': arguments},
    );
    return result;
  }

  /// Async variant of [timeSubprocess] for callers that use
  /// [Process.run] or `processManager.run`.
  Future<ProcessResult> timeSubprocessAsync({
    required String executable,
    required List<String> arguments,
    required int pid,
    required int tid,
    required Future<ProcessResult> Function() runner,
  }) async {
    final startMicros = DateTime.now().microsecondsSinceEpoch;
    try {
      return await runner();
    } finally {
      addCompleteEvent(
        name: _basename(executable),
        cat: 'subprocess',
        pid: pid,
        tid: tid,
        startMicros: startMicros,
        endMicros: DateTime.now().microsecondsSinceEpoch,
        args: <String, Object?>{'argv': arguments},
      );
    }
  }

  /// Records an HTTP request span. Name is "METHOD host" so requests to
  /// the same host collapse visually in Perfetto. [args] augments the
  /// standard `{method, host}` with optional `status`, `contentLength`,
  /// `error`.
  void recordNetworkSpan({
    required String method,
    required String host,
    required int pid,
    required int tid,
    required int startMicros,
    required int endMicros,
    int? status,
    int? contentLength,
    String? error,
  }) {
    addCompleteEvent(
      name: '$method $host',
      cat: 'network',
      pid: pid,
      tid: tid,
      startMicros: startMicros,
      endMicros: endMicros,
      args: <String, Object?>{
        'method': method,
        'host': host,
        if (status != null) 'status': status,
        if (contentLength != null) 'contentLength': contentLength,
        if (error != null) 'error': error,
      },
    );
  }

  /// Reads a trace JSON file written by a subprocess and appends its
  /// events (complete spans, metadata, and flow events) as-is.
  void mergeEventsFromFile(File file) {
    if (!file.existsSync()) {
      return;
    }
    try {
      final decoded = json.decode(file.readAsStringSync());
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map<String, Object?>) {
          _events.add(item);
        }
      }
    } on FormatException {
      // Corrupt trace — skip it rather than abort the outer build.
    }
  }

  /// Writes events to [file] as a JSON array, merging with any events
  /// already there. Existing non-list / unreadable content is
  /// overwritten; missing parent directories are created.
  void writeToFile(File file) {
    final merged = <Map<String, Object?>>[];
    if (file.existsSync()) {
      try {
        final decoded = json.decode(file.readAsStringSync());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, Object?>) {
              merged.add(item);
            }
          }
        }
      } on FormatException {
        // Ignore corrupt existing trace — overwrite with our events.
      }
    }
    merged.addAll(_events);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync(json.encode(merged));
  }
}

String _basename(String path) {
  final sep = path.lastIndexOf(Platform.pathSeparator);
  return sep < 0 ? path : path.substring(sep + 1);
}
