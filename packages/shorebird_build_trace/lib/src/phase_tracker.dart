import 'package:shorebird_build_trace/src/build_tracer.dart';

/// Records a span each time a new named phase begins. Used when parsing
/// a subprocess's verbose output to attribute time to sub-phases of a
/// larger operation (e.g. `pod install: analyzing`, `pod install:
/// downloading`, ...).
///
/// Call [transitionTo] with each new phase name as you detect it; the
/// previous phase's span is emitted at that point. Call
/// `transitionTo(null)` (or just [end]) when the enclosing subprocess
/// exits so the last phase's span is flushed.
class PhaseTracker {
  /// Creates a [PhaseTracker] that will record spans on [tracer]
  /// for each phase transition, using ([pid], [tid]) for layout and
  /// prefixing each span name with "[namePrefix]: ".
  PhaseTracker({
    required this.tracer,
    required this.pid,
    required this.tid,
    required this.namePrefix,
    this.cat = 'subprocess',
  });

  /// The tracer to record spans on.
  final BuildTracer tracer;

  /// Process id for emitted spans.
  final int pid;

  /// Thread id for emitted spans.
  final int tid;

  /// Span name is `"$namePrefix: $phase"`.
  final String namePrefix;

  /// Span category.
  final String cat;

  String? _currentPhase;
  int? _currentStartMicros;

  /// Moves to [nextPhase]. If a previous phase was in progress, its span
  /// is recorded first. Pass null to close the current phase without
  /// starting a new one.
  void transitionTo(String? nextPhase) {
    final now = DateTime.now().microsecondsSinceEpoch;
    // Pull into locals so flow analysis promotes them to non-null; the
    // outer variables don't promote inside a closure context.
    final previousPhase = _currentPhase;
    final previousStart = _currentStartMicros;
    if (previousPhase != null && previousStart != null) {
      tracer.addCompleteEvent(
        name: '$namePrefix: $previousPhase',
        cat: cat,
        pid: pid,
        tid: tid,
        startMicros: previousStart,
        endMicros: now,
      );
    }
    _currentPhase = nextPhase;
    _currentStartMicros = nextPhase == null ? null : now;
  }

  /// Closes the current phase (if any). Shorthand for
  /// `transitionTo(null)`.
  void end() => transitionTo(null);
}
