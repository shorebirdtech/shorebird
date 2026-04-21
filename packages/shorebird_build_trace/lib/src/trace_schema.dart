/// String-level API contract between the trace producers (flutter_tools,
/// aot_tools, CocoaPods wrapper, the Gradle init script) and the trace
/// consumer (shorebird_cli's `build_trace_summary.dart`).
///
/// Once a name lands in a shipped flutter or aot_tools, shorebird_cli
/// has to understand it across every version pin that ships with a
/// Shorebird release. So:
///
/// * **Never rename** a constant here. Add a new one and have shorebird
///   recognize both.
/// * **Don't reuse** a removed constant's value for a different meaning
///   for the same reason.
/// * The Groovy init script (`shorebird_trace_init.gradle` in the
///   flutter fork) can't import Dart — its literals are hand-kept in
///   sync with this file. The init script carries a comment pointing
///   here.
library;

/// Chrome Trace Event `cat` values emitted by the producers.
///
/// Producers emit via [wireName]. Consumers (shorebird_cli) parse via
/// [tryParse], which returns null for unknown values so callers can
/// map them to [TraceCategory.unknown] and the switch stays
/// exhaustive. Adding a new category here is safe: older consumers
/// see it as `unknown` (dropped), newer consumers bucket it.
enum TraceCategory {
  /// Flutter-tool setup / teardown and outer `flutter build <target>`
  /// spans.
  flutter('flutter'),

  /// Native build system (Gradle, Xcode) outer spans.
  gradle('gradle'),

  /// See [gradle].
  xcode('xcode'),

  /// Per-task events emitted by `shorebird_trace_init.gradle`.
  gradleTask('gradle_task'),

  /// Per-subsection events parsed from xcresulttool's structured log.
  xcodeSubsection('xcode_subsection'),

  /// `flutter assemble` target spans.
  assemble('assemble'),

  /// Child processes traced via `BuildTracer.startAndTraceSubprocess`
  /// or `BuildTracer.timeSubprocess` — also the category the
  /// CocoaPods wrapper emits phase spans under.
  subprocess('subprocess'),

  /// HTTP request spans (artifact fetches + auth/upload).
  network('network'),

  /// Consumer-side fallback for a category emitted by a future
  /// producer version that this consumer doesn't yet recognize. Never
  /// emitted on the wire.
  unknown('');

  const TraceCategory(this.wireName);

  /// The exact string a producer emits on the `cat` field. Read by
  /// consumers via [tryParse].
  final String wireName;

  /// Total parse: returns [unknown] for a null or unrecognized wire
  /// value so consumers can switch exhaustively without coercing.
  static TraceCategory parse(String? wire) {
    if (wire == null) return unknown;
    for (final c in values) {
      if (c != unknown && c.wireName == wire) return c;
    }
    return unknown;
  }
}

/// Classification of Gradle task names performed by
/// `shorebird_trace_init.gradle`, emitted in each gradle_task event's
/// `args["kind"]`. Consumer-side enum with the same forward-compat
/// rules as [TraceCategory].
enum GradleTaskKind {
  /// Kotlin compilation tasks.
  kotlinCompile('kotlin_compile'),

  /// Java compilation tasks (including AGP's precompile scaffolding).
  javaCompile('java_compile'),

  /// DEX conversion.
  dex('dex'),

  /// Resource processing / manifest merging / R-file generation.
  resources('resources'),

  /// AGP artifact transforms.
  transform('transform'),

  /// R8 / minification.
  r8Minify('r8_minify'),

  /// Android lint.
  lint('lint'),

  /// Native library linking.
  nativeLink('native_link'),

  /// Flutter gradle plugin's own tasks.
  flutterGradlePlugin('flutter_gradle_plugin'),

  /// `bundle*` tasks.
  bundle('bundle'),

  /// `package*` tasks (non-plugin).
  packaging('packaging'),

  /// AIDL.
  aidl('aidl'),

  /// Gradle's per-plugin / per-variant scaffolding (metadata, proguard
  /// rule export, pre-/post-compile bookkeeping).
  gradleScaffold('gradle_scaffold'),

  /// Catch-all for tasks the init script's classifier didn't match.
  /// Also the consumer-side fallback for unrecognized wire values.
  other('other');

  const GradleTaskKind(this.wireName);

  /// The exact string the init script emits on `args["kind"]`.
  final String wireName;

  /// Total parse: returns [other] for a null or unrecognized wire
  /// value so consumers can switch exhaustively without coercing.
  static GradleTaskKind parse(String? wire) {
    if (wire == null) return other;
    for (final k in values) {
      if (k.wireName == wire) return k;
    }
    return other;
  }
}

/// Span name prefixes emitted by the producers. These are format
/// strings ("gradle " then the task name) rather than enumerated
/// values, so they stay as constants; see [TraceCategory] /
/// [GradleTaskKind] for the enumerated vocabularies.
class TraceNames {
  // coverage:ignore-start
  /// Private constructor — [TraceNames] only holds static members, so an
  /// instance is never created (and this line is never run).
  TraceNames._();
  // coverage:ignore-end

  /// Prefix for the outer flutter build span. Span name is
  /// `"flutter build <target>"` (target = apk / appbundle / ios / ipa).
  /// shorebird matches with `startsWith`.
  static const String flutterBuildSpanPrefix = 'flutter build ';

  /// Prefix for the outer gradle span. Span name is
  /// `"gradle <assembleTask>"`.
  static const String gradleSpanPrefix = 'gradle ';

  /// Prefix for the outer xcode span. Span name is
  /// `"xcode <action>"` (build / archive / install).
  static const String xcodeSpanPrefix = 'xcode ';

  /// Name prefix the CocoaPods phase tracker emits phase spans under.
  /// Full span name shorebird matches is `"pod install: <phase>"`.
  static const String podInstallNamePrefix = 'pod install';

  /// Name of the outer `pod install` span (emitted separately from
  /// phase sub-spans).
  static const String podInstallSpanName = 'pod install';
}

/// Phases identified by the CocoaPods verbose-output parser. Producer
/// side (flutter_tools) picks the value, [PhaseTracker] stringifies it
/// with [TraceNames.podInstallNamePrefix] as prefix. Consumer side
/// (shorebird_cli) matches the assembled span name against this enum's
/// [wireName]s.
enum PodInstallPhase {
  /// Seen when `pod install` logs `Analyzing dependencies`.
  analyzing('analyzing'),

  /// Seen when `pod install` logs `Downloading dependencies`.
  downloading('downloading'),

  /// Seen when `pod install` logs `Generating Pods project`.
  generating('generating'),

  /// Seen when `pod install` logs `Integrating client project`.
  integrating('integrating'),

  /// Consumer-side fallback for a phase name a future producer
  /// version might emit but this consumer doesn't recognize. Never
  /// emitted on the wire.
  other('');

  const PodInstallPhase(this.wireName);

  /// The phase name used in the emitted span (`"pod install: <wireName>"`).
  final String wireName;

  /// Total parse: returns [other] for a null or unrecognized wire
  /// value so consumers can bucket uniformly without coercing.
  static PodInstallPhase parse(String? wire) {
    if (wire == null) return other;
    for (final p in values) {
      if (p != other && p.wireName == wire) return p;
    }
    return other;
  }
}
