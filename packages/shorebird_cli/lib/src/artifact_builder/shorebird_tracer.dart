import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';

/// A single event in the Chrome Trace Event Format, written by Shorebird
/// itself (not Flutter). Accumulated in memory during a CLI invocation and
/// merged into the Flutter-written trace file at summary-write time.
class ShorebirdTraceEvent {
  /// {@macro shorebird_trace_event}
  ShorebirdTraceEvent({
    required this.name,
    required this.category,
    required this.startMicros,
    required this.durationMicros,
    this.threadId = 5,
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

  /// Thread id used by Perfetto to lay out events in swimlanes. We reserve
  /// `5` for Shorebird so it doesn't collide with flutter tool (1), native
  /// outer (2), flutter assemble (3), or gradle tasks (4).
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
    'pid': 1,
    'tid': threadId,
    'args': ?args,
  };
}

/// Collects Shorebird-side trace events during a CLI invocation.
///
/// Scope-held so all layers (HTTP client, subprocess wrapper, command-level
/// phases) can write into the same collector, and the summary writer in
/// `ArtifactBuilder` can merge the accumulated events into Flutter's trace
/// file before parsing it.
class ShorebirdTracer {
  final List<ShorebirdTraceEvent> _events = [];

  /// Unmodifiable view of the events recorded so far.
  List<ShorebirdTraceEvent> get events => List.unmodifiable(_events);

  /// Record a single completed event. Prefer [span] for measuring the
  /// duration of a block of code.
  void addEvent(ShorebirdTraceEvent event) => _events.add(event);

  /// Run [body], timing it, and record a [ShorebirdTraceEvent] for the
  /// duration. Always returns [body]'s result (rethrows on exception; the
  /// event is still recorded).
  Future<T> span<T>({
    required String name,
    required String category,
    required Future<T> Function() body,
    Map<String, Object?>? args,
    int threadId = 5,
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
          threadId: threadId,
          args: args,
        ),
      );
    }
  }

  /// Append all accumulated events to [traceFile] (which must already be a
  /// JSON array of Chrome Trace Event Format events, as written by Flutter).
  /// No-op if the file doesn't exist or is malformed.
  void mergeInto(File traceFile) {
    if (!traceFile.existsSync()) return;
    try {
      final decoded = jsonDecode(traceFile.readAsStringSync());
      if (decoded is! List) return;
      final merged = [...decoded, ..._events.map((e) => e.toJson())];
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
