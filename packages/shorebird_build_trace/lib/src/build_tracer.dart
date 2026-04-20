import 'dart:convert';
import 'dart:io';

import 'package:shorebird_build_trace/src/build_trace_event.dart';

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
  /// Private backing field for [current]. Producers never touch this
  /// directly — [start] / [stop] manage it, and [runAsync] wraps the
  /// two in a try/finally for callers that can afford a closure.
  static BuildTracer? _current;

  /// The tracer for the in-progress build, if any. Set by [start] (or
  /// by the [runAsync] wrapper around it) so deep layers (network,
  /// subprocess wrappers) can record spans without plumbing a
  /// parameter through every signature. Null when no producer has a
  /// build in progress.
  static BuildTracer? get current => _current;

  /// Installs [tracer] as [current]. Producers that can wrap a body
  /// in a closure should prefer [runAsync] — it pairs [start] with
  /// [stop] in a try/finally. Call [stop] when the build finishes.
  ///
  /// Throws [StateError] if a tracer is already installed: there's
  /// only one [current] at a time and overlapping producers would
  /// overwrite each other's spans. Use [runAsync] if you need nested
  /// installs (it saves/restores the prior value).
  static void start(BuildTracer tracer) {
    if (_current != null) {
      throw StateError(
        'BuildTracer already installed; call stop() before starting a new one '
        'or use runAsync() for nested installs.',
      );
    }
    _current = tracer;
  }

  /// Clears [current]. Idempotent — safe to call when nothing is
  /// installed, so error paths can invoke it unconditionally. Pair
  /// with [start].
  static void stop() {
    _current = null;
  }

  /// Runs [body] with [tracer] installed as [current] for its duration
  /// (including any async work it awaits). Unwinds on return or throw
  /// so [current] is guaranteed cleared — producers don't have to pair
  /// [start] / [stop] calls themselves.
  ///
  /// Saves and restores the prior [current] so nested calls compose.
  static Future<T> runAsync<T>(
    BuildTracer tracer,
    Future<T> Function() body,
  ) async {
    final prev = _current;
    _current = tracer;
    try {
      return await body();
    } finally {
      _current = prev;
    }
  }

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
    required DateTime start,
    required DateTime end,
    Map<String, Object?>? args,
  }) {
    _events.add(
      BuildTraceEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        start: start,
        duration: end.difference(start),
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
  /// ([pid], [tid], [at]) to a flow-end event a spawned child will
  /// emit with the same [id]. Shorebird convention uses the child's pid
  /// as the flow id so spawner and spawnee agree on the id without
  /// passing it through env vars.
  void addFlowStart({
    required int id,
    required int pid,
    required int tid,
    required DateTime at,
  }) {
    _events.add(<String, Object?>{
      'ph': 's',
      'name': 'spawn',
      'cat': 'flow',
      'id': id,
      'ts': at.microsecondsSinceEpoch,
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
    required DateTime at,
  }) {
    _events.add(<String, Object?>{
      'ph': 'f',
      'name': 'spawn',
      'cat': 'flow',
      'id': id,
      'ts': at.microsecondsSinceEpoch,
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
    final start = DateTime.now();
    try {
      return body();
    } finally {
      addCompleteEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        start: start,
        end: DateTime.now(),
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
    final start = DateTime.now();
    try {
      return await body();
    } finally {
      addCompleteEvent(
        name: name,
        cat: cat,
        pid: pid,
        tid: tid,
        start: start,
        end: DateTime.now(),
        args: args,
      );
    }
  }

  /// Adds a span describing a subprocess invocation whose timing the
  /// caller already measured. Span name is the [executable] basename;
  /// the full argv lands in `args.argv`. Prefer [timeSubprocess] /
  /// [timeSubprocessAsync] when you're *about* to run the process;
  /// this helper is for call sites that already have start/end
  /// timestamps (e.g. an existing stopwatch-around-run pattern).
  void addSubprocessEvent({
    required String executable,
    required List<String> arguments,
    required int pid,
    required int tid,
    required DateTime start,
    required DateTime end,
  }) {
    addCompleteEvent(
      name: _basename(executable),
      cat: 'subprocess',
      pid: pid,
      tid: tid,
      start: start,
      end: end,
      args: <String, Object?>{'argv': arguments},
    );
  }

  /// Emits a span that covers a subprocess invocation. [runner] should
  /// invoke [Process.runSync] (or equivalent) with [executable] and
  /// [arguments]; the span wraps it with start/end timestamps, and the
  /// executable basename + full argv end up in the Perfetto span pane.
  ProcessResult timeSubprocess({
    required String executable,
    required List<String> arguments,
    required int pid,
    required int tid,
    required ProcessResult Function() runner,
  }) {
    final start = DateTime.now();
    final result = runner();
    addCompleteEvent(
      name: _basename(executable),
      cat: 'subprocess',
      pid: pid,
      tid: tid,
      start: start,
      end: DateTime.now(),
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
    final start = DateTime.now();
    try {
      return await runner();
    } finally {
      addCompleteEvent(
        name: _basename(executable),
        cat: 'subprocess',
        pid: pid,
        tid: tid,
        start: start,
        end: DateTime.now(),
        args: <String, Object?>{'argv': arguments},
      );
    }
  }

  /// Spawns [executable] via [Process.start], waits for it, and emits
  /// metadata + subprocess span on the child's real OS pid — each
  /// subprocess shows up as its own process in Perfetto, not a row
  /// inside the parent.
  ///
  /// Returns a [ProcessResult] with the same shape [Process.run] would
  /// have produced (stdout and stderr decoded via [systemEncoding]) so
  /// callers can swap `Process.run` → this helper without changing the
  /// surrounding code.
  ///
  /// [workingDirectory] and [environment] are forwarded to
  /// [Process.start].
  Future<ProcessResult> startAndTraceSubprocess({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final start = DateTime.now();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final childPid = process.pid;
    final stdoutF = process.stdout.transform(systemEncoding.decoder).join();
    final stderrF = process.stderr.transform(systemEncoding.decoder).join();
    final exitCode = await process.exitCode;
    final streams = await Future.wait([stdoutF, stderrF]);
    final end = DateTime.now();

    final name = _basename(executable);
    addProcessNameMetadata(pid: childPid, name: name);
    addThreadNameMetadata(pid: childPid, tid: 1, name: name);
    addSubprocessEvent(
      executable: executable,
      arguments: arguments,
      pid: childPid,
      tid: 1,
      start: start,
      end: end,
    );

    return ProcessResult(childPid, exitCode, streams[0], streams[1]);
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
    required DateTime start,
    required DateTime end,
    int? status,
    int? contentLength,
    String? error,
  }) {
    addCompleteEvent(
      name: '$method $host',
      cat: 'network',
      pid: pid,
      tid: tid,
      start: start,
      end: end,
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
  ///
  /// If [existingEvents] is provided, it is used in place of re-reading
  /// [file]. Callers that have already parsed [file] (e.g. to decide
  /// whether to merge at all) can pass the parsed events here to avoid
  /// a redundant read-and-parse.
  void writeToFile(
    File file, {
    List<Map<String, Object?>>? existingEvents,
  }) {
    final merged = <Map<String, Object?>>[];
    if (existingEvents != null) {
      merged.addAll(existingEvents);
    } else if (file.existsSync()) {
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
