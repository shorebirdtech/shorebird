import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';

/// Process-wide state captured once at `main()` entry so that later code
/// (e.g. the build trace summarizer) can attribute wall-clock time to
/// Shorebird versus Flutter without plumbing a start-time parameter
/// through every layer.
class BuildTraceSession {
  /// {@macro build_trace_session}
  BuildTraceSession({required this.commandStartedAt});

  /// The wall-clock time at which the current `shorebird` invocation began.
  final DateTime commandStartedAt;

  /// The most recent [BuildTraceSummary] produced for this invocation, or
  /// null if no build trace was produced (older Flutter versions, trace
  /// file malformed, user flag off, etc.). Populated by
  /// `ArtifactBuilder._writeBuildTraceSummary` after each build; read by
  /// `release_command` / `patch_command` to attach to the metadata
  /// blob that goes up with the create-patch / update-release-status
  /// API call.
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
