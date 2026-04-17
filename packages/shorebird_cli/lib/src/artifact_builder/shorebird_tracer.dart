import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';

/// The OS process id of the current Dart process.
///
/// Trivial re-export of `dart:io`'s top-level [pid] getter so call sites
/// read as "the thing that tagged this span" rather than reaching into
/// `dart:io` for one name.
int currentProcessId() => pid;

/// Perfetto row id for network (HTTP) spans within the shorebird_cli
/// process. Local tid; no cross-repo coordination.
const int _networkTid = 1;

/// Perfetto row id for shorebird_cli's own command-level phase spans
/// (the ones recorded via [ShorebirdTracer.span]).
const int _shorebirdTid = 2;

/// A single event in the Chrome Trace Event Format, written by Shorebird
/// itself (not Flutter). Accumulated in memory during a CLI invocation and
/// merged into the Flutter-written trace file at summary-write time.
///
/// Format doc: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
///
/// Lookalike classes live in `flutter/packages/flutter_tools/lib/src/
/// build_system/build_trace.dart` and `dart-sdk/pkg/aot_tools/lib/src/
/// build_tracer.dart`; they all serialize to the same wire format so
/// traces merge cleanly. Keep field names and ph/ts/dur/pid/tid shape
/// in sync when editing.
class ShorebirdTraceEvent {
  /// {@macro shorebird_trace_event}
  ShorebirdTraceEvent({
    required this.name,
    required this.category,
    required this.startMicros,
    required this.durationMicros,
    required this.pid,
    this.threadId = _shorebirdTid,
    this.args,
  });

  /// Event name (e.g. `POST api.shorebird.dev`, `process flutter build apk`).
  final String name;

  /// Free-form category used by the summarizer to bucket events. Current
  /// values: `network`, `process`, `shorebird`.
  final String category;

  /// Start time in wall-clock microseconds since epoch (matches the timebase
  /// Flutter uses for its own events).
  final int startMicros;

  /// Duration in microseconds.
  final int durationMicros;

  /// Real OS pid of the process emitting the event (shorebird_cli's own).
  final int pid;

  /// Perfetto row within [pid].
  final int threadId;

  /// Optional free-form args. Keys must be safe to upload — no paths, user
  /// data, or identifiers.
  final Map<String, Object?>? args;

  /// JSON-encodable form suitable for appending to a Chrome Trace Event
  /// Format file.
  Map<String, Object?> toJson() => {
    'name': name,
    'cat': category,
    'ph': 'X',
    'ts': startMicros,
    'dur': durationMicros,
    'pid': pid,
    'tid': threadId,
    'args': ?args,
  };
}

/// Collects Shorebird-side trace events during a CLI invocation and
/// emits them as Chrome Trace Event Format entries (complete spans,
/// process/thread name metadata, and flow-start events at subprocess
/// spawn sites) into the Flutter-written trace file.
///
/// Scope-held so all layers (HTTP client, subprocess wrapper, command-level
/// phases) can write into the same collector, and the summary writer in
/// `ArtifactBuilder` can merge the accumulated events into Flutter's trace
/// file before parsing it.
class ShorebirdTracer {
  /// Raw JSON maps so complete spans, metadata (`ph: "M"`), and flow
  /// events (`ph: "s"`) share the buffer without fighting a stricter
  /// typed API.
  final List<Map<String, Object?>> _events = [];

  /// Real pid of the shorebird_cli process — captured at construction
  /// so every event emitted through this tracer is tagged with it.
  final int _pid = currentProcessId();

  /// Unmodifiable view of the events recorded so far.
  List<Map<String, Object?>> get events => List.unmodifiable(_events);

  /// Record a single completed network span on the shorebird_cli row.
  void addNetworkEvent({
    required String name,
    required int startMicros,
    required int durationMicros,
    Map<String, Object?>? args,
  }) {
    _events.add(
      ShorebirdTraceEvent(
        name: name,
        category: 'network',
        startMicros: startMicros,
        durationMicros: durationMicros,
        pid: _pid,
        threadId: _networkTid,
        args: args,
      ).toJson(),
    );
  }

  /// Record a completed span via a pre-built [ShorebirdTraceEvent]. Used
  /// by tests; production code should prefer [addNetworkEvent] or [span].
  void addEvent(ShorebirdTraceEvent event) => _events.add(event.toJson());

  /// Run [body], timing it, and record a [ShorebirdTraceEvent] for the
  /// duration on the shorebird_cli row. Always returns [body]'s result
  /// (rethrows on exception; the event is still recorded).
  Future<T> span<T>({
    required String name,
    required String category,
    required Future<T> Function() body,
    Map<String, Object?>? args,
  }) async {
    final start = DateTime.now().microsecondsSinceEpoch;
    try {
      return await body();
    } finally {
      final end = DateTime.now().microsecondsSinceEpoch;
      _events.add(
        ShorebirdTraceEvent(
          name: name,
          category: category,
          startMicros: start,
          durationMicros: end - start,
          pid: _pid,
          args: args,
        ).toJson(),
      );
    }
  }

  /// Emits a flow-start event (`ph: "s"`) at [atMicros] on
  /// ([_pid], [fromTid]) with id = [id]. Shorebird convention uses the
  /// child process's real pid as the flow id so the child emits the
  /// matching `ph: "f"` with the same id without any plumbing.
  void addSpawnFlowStart({
    required int id,
    required int atMicros,
    int fromTid = _shorebirdTid,
  }) {
    _events.add(<String, Object?>{
      'ph': 's',
      'name': 'spawn',
      'cat': 'flow',
      'id': id,
      'ts': atMicros,
      'pid': _pid,
      'tid': fromTid,
      'bp': 'e',
    });
  }

  /// Append all accumulated events to [traceFile] (which must already be
  /// a JSON array of Chrome Trace Event Format events, as written by
  /// Flutter). Also emits `process_name` / `thread_name` metadata events
  /// so Perfetto labels our rows. No-op if the file doesn't exist or is
  /// malformed.
  void mergeInto(File traceFile) {
    if (!traceFile.existsSync()) return;
    try {
      final decoded = jsonDecode(traceFile.readAsStringSync());
      if (decoded is! List) return;
      final metadata = <Map<String, Object?>>[
        {
          'name': 'process_name',
          'ph': 'M',
          'pid': _pid,
          'args': <String, Object?>{'name': 'shorebird_cli'},
        },
        {
          'name': 'thread_name',
          'ph': 'M',
          'pid': _pid,
          'tid': _networkTid,
          'args': <String, Object?>{'name': 'network'},
        },
        {
          'name': 'thread_name',
          'ph': 'M',
          'pid': _pid,
          'tid': _shorebirdTid,
          'args': <String, Object?>{'name': 'shorebird_cli'},
        },
      ];
      final merged = [...decoded, ...metadata, ..._events];
      traceFile.writeAsStringSync(jsonEncode(merged));
    } on FormatException {
      // Malformed trace — leave it alone rather than overwriting useful
      // Flutter-written data with our merge.
    }
  }
}

/// A reference to a [ShorebirdTracer] instance. One instance per `shorebird`
/// invocation, seeded in `main()`.
final shorebirdTracerRef = create<ShorebirdTracer>(ShorebirdTracer.new);

/// The [ShorebirdTracer] instance available in the current zone.
ShorebirdTracer get shorebirdTracer => read(shorebirdTracerRef);
