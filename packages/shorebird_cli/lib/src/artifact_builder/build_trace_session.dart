import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';

/// Process-wide state for the build-trace feature. Populated by
/// `release_command` / `patch_command` at the start of a build so that
/// `ArtifactBuilder`, `AotTools`, and the HTTP client can emit events
/// into the same trace without threading a trace-file path through
/// every API.
class BuildTraceSession {
  /// {@macro build_trace_session}
  BuildTraceSession({required this.commandStartedAt});

  /// The wall-clock time at which the current `shorebird` invocation began.
  final DateTime commandStartedAt;

  /// The Chrome Trace Event Format JSON file that producers
  /// (`flutter build --shorebird-trace`, `aot_tools --trace`, and
  /// shorebird_cli's own spans) append to. Null when tracing is not
  /// supported on the pinned Flutter or hasn't been set up yet.
  ///
  /// Set once by `ArtifactBuilder.prepareBuildTrace`; read by build
  /// methods, `AotTools._exec`, and `ArtifactBuilder.writeBuildTraceSummary`.
  File? traceFile;

  /// Platform identifier ("android", "ios", "linux", "macos", "windows")
  /// used to name the trace and summary files and to pick
  /// platform-specific accumulators in the summary.
  String? platform;

  /// The [BuildTraceSummary] produced by the most recent
  /// `writeBuildTraceSummary` call, or null if no summary was written
  /// (unsupported Flutter pin, trace file malformed, etc.).
  ///
  /// Read by `release_command.finalizeRelease` / `patch_command.createPatch`
  /// to attach the summary to the outgoing metadata blob.
  BuildTraceSummary? summary;
}

/// A reference to a [BuildTraceSession] instance. The default factory is
/// called at first read; `main()` overrides it with the real command start
/// time so ArtifactBuilder can read an accurate value.
final buildTraceSessionRef = create<BuildTraceSession>(
  () => BuildTraceSession(commandStartedAt: DateTime.now()),
);

/// The [BuildTraceSession] instance available in the current zone.
BuildTraceSession get buildTraceSession => read(buildTraceSessionRef);
