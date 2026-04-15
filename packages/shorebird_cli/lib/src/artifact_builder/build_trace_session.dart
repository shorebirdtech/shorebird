import 'package:scoped_deps/scoped_deps.dart';

/// Process-wide state captured once at `main()` entry so that later code
/// (e.g. the build trace summarizer) can attribute wall-clock time to
/// Shorebird versus Flutter without plumbing a start-time parameter
/// through every layer.
class BuildTraceSession {
  /// {@macro build_trace_session}
  BuildTraceSession({required this.commandStartedAt});

  /// The wall-clock time at which the current `shorebird` invocation began.
  final DateTime commandStartedAt;
}

/// A reference to a [BuildTraceSession] instance. The default factory is
/// called at first read; `main()` overrides it with the real command start
/// time so ArtifactBuilder can read an accurate value.
final buildTraceSessionRef = create<BuildTraceSession>(
  () => BuildTraceSession(commandStartedAt: DateTime.now()),
);

/// The [BuildTraceSession] instance available in the current zone.
BuildTraceSession get buildTraceSession => read(buildTraceSessionRef);
