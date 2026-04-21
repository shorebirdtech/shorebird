/// Chrome Trace Event Format producer for Shorebird's build-trace
/// plumbing. Used by `flutter_tools`, `dart-sdk/pkg/aot_tools`, and
/// `shorebird_cli` to emit a shared-format trace that opens in
/// https://ui.perfetto.dev.
///
/// Format doc: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU
///
/// The goal is one wire format + one set of tracing helpers across the
/// three codebases that contribute events. Each consumer configures a
/// single [BuildTracer] and emits via the provided helpers
/// ([BuildTracer.trace], [BuildTracer.traceAsync],
/// [BuildTracer.timeSubprocess], [BuildTracer.timeSubprocessAsync],
/// [BuildTracer.recordNetworkSpan], [PhaseTracker]); this library owns
/// the JSON shape, the metadata/flow event types, and merging with
/// existing trace files.
library;

export 'src/build_trace_event.dart';
export 'src/build_tracer.dart';
export 'src/phase_tracker.dart';
export 'src/process_id.dart';
export 'src/run_subprocess.dart';
export 'src/trace_schema.dart';
