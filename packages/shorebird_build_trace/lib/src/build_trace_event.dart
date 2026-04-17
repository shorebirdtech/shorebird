/// A single event in a Chrome Trace Event Format trace.
///
/// Format doc: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
class BuildTraceEvent {
  /// Creates a complete (`ph: "X"`) span.
  BuildTraceEvent({
    required this.name,
    required this.cat,
    required this.ts,
    required this.dur,
    required this.pid,
    required this.tid,
    this.args,
  });

  // `!` is the lint-preferred pattern for required JSON fields: the trace
  // format guarantees these, and the assertion fails loudly rather than
  // silently coercing null through `as int`.
  /// Parses a single event from its JSON representation.
  factory BuildTraceEvent.fromJson(Map<String, Object?> json) {
    return BuildTraceEvent(
      name: json['name']! as String,
      cat: json['cat']! as String,
      ts: json['ts']! as int,
      dur: json['dur']! as int,
      pid: json['pid']! as int,
      tid: json['tid']! as int,
      args: json['args'] as Map<String, Object?>?,
    );
  }

  /// The span name displayed in Perfetto.
  final String name;

  /// Event category (Perfetto filter / color).
  final String cat;

  /// Wall-clock start of the span in microseconds since epoch (matches
  /// Perfetto's clock).
  final int ts;

  /// Duration of the span in microseconds.
  final int dur;

  /// OS process id of the process that produced the event.
  final int pid;

  /// Thread id within [pid]. Logical row in Perfetto for the producer;
  /// need not correspond to an OS thread.
  final int tid;

  /// Freeform metadata shown in the Perfetto span details pane.
  final Map<String, Object?>? args;

  /// JSON form of the event.
  Map<String, Object?> toJson() => <String, Object?>{
    'ph': 'X',
    'name': name,
    'cat': cat,
    'ts': ts,
    'dur': dur,
    'pid': pid,
    'tid': tid,
    if (args != null) 'args': args,
  };
}
